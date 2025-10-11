defmodule FinancialAgent.Workers.GmailSyncWorker do
  @moduledoc """
  Oban worker that syncs Gmail messages for a user.

  This worker:
  1. Fetches the user's Google OAuth credential
  2. Lists recent Gmail messages (last 7 days by default)
  3. Fetches full message details for each message
  4. Stores messages as chunks in the database
  5. Enqueues EmbeddingWorker jobs for each chunk

  ## Options
  - `:user_id` (required) - The UUID of the user to sync
  - `:max_messages` (optional) - Maximum number of messages to fetch (default: 100)
  - `:days_back` (optional) - How many days back to fetch messages (default: 7)
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 3,
    unique: [
      period: 60,
      states: [:available, :scheduled, :executing]
    ]

  alias FinancialAgent.Accounts
  alias FinancialAgent.Clients.GmailClient
  alias FinancialAgent.RAG
  alias FinancialAgent.Workers.EmbeddingWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    max_messages = Map.get(args, "max_messages", 100)
    days_back = Map.get(args, "days_back", 7)

    Logger.info("Starting Gmail sync for user #{user_id}")

    with {:ok, credential} <- get_google_credential(user_id),
         {:ok, messages} <- fetch_messages(credential, max_messages, days_back),
         {:ok, chunks} <- store_messages(user_id, messages),
         {:ok, _jobs} <- enqueue_embedding_jobs(chunks) do
      Logger.info("Gmail sync completed for user #{user_id}. Synced #{length(messages)} messages.")
      {:ok, %{synced_count: length(messages), chunk_count: length(chunks)}}
    else
      {:error, :no_credential} ->
        Logger.warning("No Google credential found for user #{user_id}")
        {:error, :no_credential}

      {:error, reason} = error ->
        Logger.error("Gmail sync failed for user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  defp get_google_credential(user_id) do
    case Accounts.get_credential(user_id, "google") do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  defp fetch_messages(credential, max_messages, days_back) do
    client = GmailClient.new(credential.access_token)

    # Calculate date for query (e.g., "after:2024/01/01")
    cutoff_date =
      DateTime.utc_now()
      |> DateTime.add(-days_back, :day)
      |> Calendar.strftime("%Y/%m/%d")

    query = "after:#{cutoff_date}"

    case GmailClient.list_messages(client, q: query, maxResults: max_messages) do
      {:ok, %{"messages" => message_list}} when is_list(message_list) ->
        # Fetch full details for each message
        messages = Enum.map(message_list, fn %{"id" => message_id} ->
          case GmailClient.get_message(client, message_id) do
            {:ok, message} -> message
            {:error, _reason} -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)

        {:ok, messages}

      {:ok, _response} ->
        # No messages found
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_messages(user_id, messages) do
    chunks = Enum.map(messages, fn message ->
      attrs = build_chunk_attrs(user_id, message)

      case RAG.create_chunk(attrs) do
        {:ok, chunk} -> chunk
        {:error, changeset} ->
          Logger.error("Failed to create chunk: #{inspect(changeset.errors)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)

    {:ok, chunks}
  end

  defp build_chunk_attrs(user_id, message) do
    message_id = message["id"]
    thread_id = message["threadId"]

    # Extract headers
    headers = GmailClient.extract_headers(message)
    subject = headers.subject || "(No Subject)"
    from = headers.from || "Unknown"
    to = headers.to || ""
    date = headers.date || ""

    # Extract message body
    content = GmailClient.extract_text_content(message)

    # Build combined text for embedding
    text = """
    Subject: #{subject}
    From: #{from}
    To: #{to}
    Date: #{date}

    #{content}
    """

    # Build metadata
    metadata = %{
      source: "gmail",
      message_id: message_id,
      thread_id: thread_id,
      subject: subject,
      from: from,
      to: to,
      date: date
    }

    %{
      user_id: user_id,
      source: "gmail",
      source_id: message_id,
      content: text,
      metadata: metadata
    }
  end

  defp enqueue_embedding_jobs(chunks) do
    jobs = Enum.map(chunks, fn chunk ->
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
