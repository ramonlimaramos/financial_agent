defmodule FinancialAgent.Workers.HubSpotSyncWorker do
  @moduledoc """
  Oban worker that syncs HubSpot CRM data for a user.

  This worker:
  1. Fetches the user's HubSpot OAuth credential
  2. Lists HubSpot contacts
  3. Stores contacts as chunks in the database
  4. Enqueues EmbeddingWorker jobs for each chunk

  ## Options
  - `:user_id` (required) - The UUID of the user to sync
  - `:limit` (optional) - Maximum number of contacts to fetch per request (default: 100)
  - `:max_pages` (optional) - Maximum number of pages to fetch (default: 10)
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 3,
    unique: [
      period: 60,
      states: [:available, :scheduled, :executing]
    ]

  alias FinancialAgent.Accounts
  alias FinancialAgent.Clients.HubSpotClient
  alias FinancialAgent.RAG
  alias FinancialAgent.Workers.EmbeddingWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    limit = Map.get(args, "limit", 100)
    max_pages = Map.get(args, "max_pages", 10)

    Logger.info("Starting HubSpot sync for user #{user_id}")

    with {:ok, credential} <- get_hubspot_credential(user_id),
         {:ok, contacts} <- fetch_contacts(credential, limit, max_pages),
         {:ok, chunks} <- store_contacts(user_id, contacts),
         {:ok, _jobs} <- enqueue_embedding_jobs(chunks) do
      Logger.info(
        "HubSpot sync completed for user #{user_id}. Synced #{length(contacts)} contacts."
      )

      {:ok, %{synced_count: length(contacts), chunk_count: length(chunks)}}
    else
      {:error, :no_credential} ->
        Logger.warning("No HubSpot credential found for user #{user_id}")
        {:error, :no_credential}

      {:error, reason} = error ->
        Logger.error("HubSpot sync failed for user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_hubspot_credential(user_id) do
    case Accounts.get_credential(user_id, "hubspot") do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  defp fetch_contacts(credential, limit, max_pages) do
    client = HubSpotClient.new(credential.access_token)

    fetch_contacts_recursive(client, limit, max_pages, [], nil, 0)
  end

  defp fetch_contacts_recursive(_client, _limit, max_pages, acc, _offset, page)
       when page >= max_pages do
    {:ok, acc}
  end

  defp fetch_contacts_recursive(client, limit, max_pages, acc, offset, page) do
    opts = [count: limit]
    opts = if offset, do: Keyword.put(opts, :vidOffset, offset), else: opts

    case HubSpotClient.list_contacts(client, opts) do
      {:ok, %{"contacts" => contacts, "has-more" => has_more, "vid-offset" => vid_offset}} ->
        all_contacts = acc ++ contacts

        if has_more do
          fetch_contacts_recursive(client, limit, max_pages, all_contacts, vid_offset, page + 1)
        else
          {:ok, all_contacts}
        end

      {:ok, %{"contacts" => contacts}} ->
        # No pagination info, assume we're done
        {:ok, acc ++ contacts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_contacts(user_id, contacts) do
    chunks =
      Enum.map(contacts, fn contact ->
        attrs = build_chunk_attrs(user_id, contact)

        case RAG.create_chunk(attrs) do
          {:ok, chunk} ->
            chunk

          {:error, changeset} ->
            Logger.error("Failed to create chunk: #{inspect(changeset.errors)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, chunks}
  end

  defp build_chunk_attrs(user_id, contact) do
    # Extract contact properties
    properties = contact["properties"] || %{}
    vid = contact["vid"] || contact["canonical-vid"]

    firstname = get_property(properties, "firstname")
    lastname = get_property(properties, "lastname")
    email = get_property(properties, "email")
    company = get_property(properties, "company")
    phone = get_property(properties, "phone")
    jobtitle = get_property(properties, "jobtitle")
    lifecyclestage = get_property(properties, "lifecyclestage")

    # Build human-readable content
    name = [firstname, lastname] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
    name = if name == "", do: email || "Unknown Contact", else: name

    text = """
    Contact: #{name}
    Email: #{email || "N/A"}
    Company: #{company || "N/A"}
    Phone: #{phone || "N/A"}
    Job Title: #{jobtitle || "N/A"}
    Lifecycle Stage: #{lifecyclestage || "N/A"}
    """

    # Build metadata
    metadata = %{
      source: "hubspot",
      contact_id: vid,
      email: email,
      company: company,
      name: name,
      lifecycle_stage: lifecyclestage
    }

    %{
      user_id: user_id,
      source: "hubspot",
      source_id: to_string(vid),
      content: text,
      metadata: metadata
    }
  end

  defp get_property(properties, key) do
    case properties[key] do
      %{"value" => value} when is_binary(value) and value != "" -> value
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp enqueue_embedding_jobs(chunks) do
    jobs =
      Enum.map(chunks, fn chunk ->
        EmbeddingWorker.new(%{chunk_id: chunk.id})
        |> Oban.insert()
      end)

    case Enum.split_with(jobs, fn
           {:ok, _job} -> true
           {:error, _reason} -> false
         end) do
      {successful, []} ->
        {:ok, successful}

      {successful, failed} ->
        Logger.warning("Failed to enqueue #{length(failed)} embedding jobs")
        {:ok, successful}
    end
  end
end
