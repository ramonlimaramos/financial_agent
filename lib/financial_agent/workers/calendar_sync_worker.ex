defmodule FinancialAgent.Workers.CalendarSyncWorker do
  @moduledoc """
  Oban worker that syncs Google Calendar events for a user.

  This worker:
  1. Fetches the user's Google OAuth credential
  2. Lists recent calendar events (last 100 by default)
  3. Stores events as chunks in the database
  4. Enqueues EmbeddingWorker jobs for each chunk

  ## Options
  - `:user_id` (required) - The UUID of the user to sync
  - `:max_events` (optional) - Maximum number of events to fetch (default: 100)
  - `:days_back` (optional) - How many days back to fetch events (default: 30)
  - `:days_forward` (optional) - How many days forward to fetch events (default: 90)
  """

  use Oban.Worker,
    queue: :sync,
    max_attempts: 3,
    unique: [
      period: 60,
      states: [:available, :scheduled, :executing]
    ]

  alias FinancialAgent.Accounts
  alias FinancialAgent.Clients.CalendarClient
  alias FinancialAgent.RAG
  alias FinancialAgent.Workers.EmbeddingWorker

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    max_events = Map.get(args, "max_events", 100)
    days_back = Map.get(args, "days_back", 30)
    days_forward = Map.get(args, "days_forward", 90)

    Logger.info("Starting Calendar sync for user #{user_id}")

    with {:ok, credential} <- get_google_credential(user_id),
         {:ok, events} <- fetch_events(credential, max_events, days_back, days_forward),
         {:ok, chunks} <- store_events(user_id, events),
         {:ok, _jobs} <- enqueue_embedding_jobs(chunks) do
      Logger.info("Calendar sync completed for user #{user_id}. Synced #{length(events)} events.")

      {:ok, %{synced_count: length(events), chunk_count: length(chunks)}}
    else
      {:error, :no_credential} ->
        Logger.warning("No Google credential found for user #{user_id}")
        {:error, :no_credential}

      {:error, reason} = error ->
        Logger.error("Calendar sync failed for user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  @spec get_google_credential(String.t()) ::
          {:ok, Accounts.Credential.t()} | {:error, :no_credential}
  defp get_google_credential(user_id) do
    case Accounts.get_credential(user_id, "google") do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  @spec fetch_events(Accounts.Credential.t(), pos_integer(), pos_integer(), pos_integer()) ::
          {:ok, list(map())} | {:error, term()}
  defp fetch_events(credential, max_events, days_back, days_forward) do
    client = CalendarClient.new(credential.access_token)

    time_min =
      DateTime.utc_now()
      |> DateTime.add(-days_back, :day)
      |> DateTime.to_iso8601()

    time_max =
      DateTime.utc_now()
      |> DateTime.add(days_forward, :day)
      |> DateTime.to_iso8601()

    case CalendarClient.list_events(client,
           time_min: time_min,
           time_max: time_max,
           max_results: max_events
         ) do
      {:ok, %{"items" => event_list}} when is_list(event_list) ->
        {:ok, event_list}

      {:ok, _response} ->
        # No events found
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec store_events(String.t(), list(map())) :: {:ok, list(RAG.Chunk.t())}
  defp store_events(user_id, events) do
    chunks =
      Enum.map(events, fn event ->
        attrs = build_chunk_attrs(user_id, event)

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

  @spec build_chunk_attrs(String.t(), map()) :: map()
  defp build_chunk_attrs(user_id, event) do
    event_id = event["id"]
    details = CalendarClient.extract_event_details(event)

    # Build combined text for embedding
    content = build_event_content(details)

    # Build metadata
    metadata = %{
      source: "calendar",
      event_id: event_id,
      summary: details.summary,
      location: details.location,
      start_time: details.start_time,
      end_time: details.end_time,
      attendees: details.attendees,
      organizer: details.organizer,
      status: details.status,
      html_link: details.html_link
    }

    %{
      user_id: user_id,
      source: "calendar",
      source_id: event_id,
      content: content,
      metadata: metadata
    }
  end

  @spec build_event_content(map()) :: String.t()
  defp build_event_content(details) do
    formatted_date = format_event_date(details.start_time, details.end_time)
    attendees_text = format_attendees(details.attendees)

    """
    Event: #{details.summary}
    Date: #{formatted_date}
    Location: #{if details.location != "", do: details.location, else: "Not specified"}
    Organizer: #{if details.organizer != "", do: details.organizer, else: "Unknown"}
    #{if attendees_text != "", do: "Attendees: #{attendees_text}", else: ""}

    #{if details.description != "", do: "Description:\n#{details.description}", else: ""}
    """
    |> String.trim()
  end

  @spec format_event_date(String.t() | nil, String.t() | nil) :: String.t()
  defp format_event_date(nil, nil), do: "Date not specified"

  defp format_event_date(start_time, end_time) when is_binary(start_time) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(start_time),
         {:ok, end_dt, _} <- DateTime.from_iso8601(end_time) do
      start_formatted = Calendar.strftime(start_dt, "%B %d, %Y at %I:%M %p")
      end_formatted = Calendar.strftime(end_dt, "%I:%M %p")
      "#{start_formatted} - #{end_formatted}"
    else
      _ -> "#{start_time} - #{end_time}"
    end
  end

  defp format_event_date(start_time, _end_time), do: start_time

  @spec format_attendees(list(String.t())) :: String.t()
  defp format_attendees([]), do: ""
  defp format_attendees(attendees), do: Enum.join(attendees, ", ")

  @spec enqueue_embedding_jobs(list(RAG.Chunk.t())) :: {:ok, list()} | {:error, term()}
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
