defmodule FinancialAgent.Clients.CalendarClient do
  @moduledoc """
  Tesla-based HTTP client for interacting with Google Calendar API.

  Handles authentication, rate limiting, and common Calendar operations
  like fetching events from the user's primary calendar.
  """

  use Tesla

  require Logger

  @base_url "https://www.googleapis.com/calendar/v3"

  @type event_list_opts :: [
          calendar_id: String.t(),
          time_min: String.t(),
          time_max: String.t(),
          max_results: pos_integer(),
          single_events: boolean(),
          order_by: String.t()
        ]

  @type event :: %{
          id: String.t(),
          summary: String.t(),
          description: String.t(),
          location: String.t(),
          start: map(),
          end: map(),
          attendees: list(),
          organizer: map()
        }

  @doc """
  Creates a new Calendar client with the provided access token.

  ## Examples

      iex> client = CalendarClient.new("access_token_here")
  """
  @spec new(String.t()) :: Tesla.Client.t()
  def new(access_token) do
    middleware = [
      {Tesla.Middleware.BaseUrl, @base_url},
      {Tesla.Middleware.Headers, [{"authorization", "Bearer #{access_token}"}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 3,
       max_delay: 4_000,
       should_retry: fn
         {:ok, %{status: status}} when status in [429, 500, 502, 503] -> true
         {:ok, _} -> false
         {:error, _} -> true
       end}
    ]

    Tesla.client(middleware)
  end

  @doc """
  Lists events from the user's calendar.

  ## Options

    * `:calendar_id` - Calendar ID to fetch events from (default: "primary")
    * `:time_min` - Lower bound for event start time (ISO8601 format)
    * `:time_max` - Upper bound for event end time (ISO8601 format)
    * `:max_results` - Maximum number of events to return (default: 100)
    * `:single_events` - Expand recurring events (default: true)
    * `:order_by` - Order results by startTime (default: "startTime")

  ## Examples

      iex> client = CalendarClient.new(token)
      iex> CalendarClient.list_events(client, max_results: 50)
      {:ok, %{"items" => [...]}}
  """
  @spec list_events(Tesla.Client.t(), event_list_opts()) :: {:ok, map()} | {:error, term()}
  def list_events(client, opts \\ []) do
    calendar_id = Keyword.get(opts, :calendar_id, "primary")

    query_params = %{
      "maxResults" => Keyword.get(opts, :max_results, 100),
      "singleEvents" => Keyword.get(opts, :single_events, true),
      "orderBy" => Keyword.get(opts, :order_by, "startTime")
    }

    query_params = add_optional_param(query_params, "timeMin", Keyword.get(opts, :time_min))
    query_params = add_optional_param(query_params, "timeMax", Keyword.get(opts, :time_max))

    case Tesla.get(client, "/calendars/#{calendar_id}/events", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Calendar API list_events error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("Calendar API list_events network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets a single event from the calendar.

  ## Examples

      iex> client = CalendarClient.new(token)
      iex> CalendarClient.get_event(client, "primary", "event_id_123")
      {:ok, %{"id" => "event_id_123", "summary" => "Meeting"}}
  """
  @spec get_event(Tesla.Client.t(), String.t(), String.t()) ::
          {:ok, event()} | {:error, term()}
  def get_event(client, calendar_id, event_id) do
    case Tesla.get(client, "/calendars/#{calendar_id}/events/#{event_id}") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Calendar API get_event error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("Calendar API get_event network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Extracts event details from a Calendar API event response.

  ## Examples

      iex> event = %{"summary" => "Meeting", "start" => %{"dateTime" => "2025-10-12T10:00:00Z"}}
      iex> CalendarClient.extract_event_details(event)
      %{summary: "Meeting", start_time: "2025-10-12T10:00:00Z", ...}
  """
  @spec extract_event_details(map()) :: map()
  def extract_event_details(event) do
    %{
      summary: Map.get(event, "summary", "(No Title)"),
      description: Map.get(event, "description", ""),
      location: Map.get(event, "location", ""),
      start_time: extract_datetime(event, "start"),
      end_time: extract_datetime(event, "end"),
      attendees: extract_attendees(event),
      organizer: extract_organizer(event),
      status: Map.get(event, "status", "confirmed"),
      html_link: Map.get(event, "htmlLink", "")
    }
  end

  # Private functions

  @spec add_optional_param(map(), String.t(), any()) :: map()
  defp add_optional_param(params, _key, nil), do: params
  defp add_optional_param(params, key, value), do: Map.put(params, key, value)

  @spec extract_datetime(map(), String.t()) :: String.t() | nil
  defp extract_datetime(event, field) do
    case get_in(event, [field]) do
      %{"dateTime" => datetime} -> datetime
      %{"date" => date} -> date
      _ -> nil
    end
  end

  @spec extract_attendees(map()) :: list(String.t())
  defp extract_attendees(%{"attendees" => attendees}) when is_list(attendees) do
    Enum.map(attendees, fn attendee ->
      Map.get(attendee, "email", "")
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp extract_attendees(_), do: []

  @spec extract_organizer(map()) :: String.t()
  defp extract_organizer(%{"organizer" => %{"email" => email}}), do: email
  defp extract_organizer(_), do: ""
end
