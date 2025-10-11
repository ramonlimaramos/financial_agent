defmodule FinancialAgent.Clients.GmailClient do
  @moduledoc """
  Tesla-based HTTP client for interacting with Gmail API.

  Handles authentication, rate limiting, and common Gmail operations
  like fetching messages and message details.
  """

  use Tesla

  require Logger

  @base_url "https://gmail.googleapis.com/gmail/v1"

  @type message_list_opts :: [
          max_results: pos_integer(),
          page_token: String.t(),
          q: String.t()
        ]

  @type message :: %{
          id: String.t(),
          thread_id: String.t(),
          label_ids: [String.t()],
          snippet: String.t(),
          payload: map(),
          internal_date: String.t()
        }

  @doc """
  Creates a new Gmail client with the provided access token.

  ## Examples

      iex> client = GmailClient.new("access_token_here")
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
  Lists messages in the user's mailbox.

  ## Options

    * `:max_results` - Maximum number of messages to return (default: 100)
    * `:page_token` - Token to retrieve a specific page of results
    * `:q` - Query string for filtering messages (Gmail search syntax)

  ## Examples

      iex> client = GmailClient.new(token)
      iex> GmailClient.list_messages(client, max_results: 10)
      {:ok, %{messages: [...], next_page_token: "..."}}

      iex> GmailClient.list_messages(client, q: "is:unread")
      {:ok, %{messages: [...]}}
  """
  @spec list_messages(Tesla.Client.t(), message_list_opts()) ::
          {:ok, map()} | {:error, term()}
  def list_messages(client, opts \\ []) do
    query_params =
      opts
      |> Keyword.put_new(:max_results, 100)
      |> Enum.into(%{})
      |> Map.new(fn {k, v} -> {to_camel_case(k), v} end)

    case Tesla.get(client, "/users/me/messages", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Gmail API list_messages error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("Gmail API list_messages network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets the full message details including headers and body.

  ## Options

    * `:format` - Format of the message to return (default: "full")
      - "minimal" - Returns only id and threadId
      - "full" - Returns the full email message including headers and body
      - "raw" - Returns the raw MIME message
      - "metadata" - Returns message metadata (headers) without body

  ## Examples

      iex> client = GmailClient.new(token)
      iex> GmailClient.get_message(client, "message_id_123")
      {:ok, %{id: "message_id_123", payload: %{...}}}
  """
  @spec get_message(Tesla.Client.t(), String.t(), keyword()) ::
          {:ok, message()} | {:error, term()}
  def get_message(client, message_id, opts \\ []) do
    format = Keyword.get(opts, :format, "full")

    case Tesla.get(client, "/users/me/messages/#{message_id}", query: [format: format]) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("Gmail API get_message error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("Gmail API get_message network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Extracts plain text content from a Gmail message payload.

  Handles both simple messages and multipart MIME messages.

  ## Examples

      iex> message = %{payload: %{body: %{data: "SGVsbG8gV29ybGQ="}}}
      iex> GmailClient.extract_text_content(message)
      "Hello World"
  """
  @spec extract_text_content(message()) :: String.t()
  def extract_text_content(%{"payload" => payload}) do
    case payload do
      %{"body" => %{"data" => data}} when is_binary(data) and data != "" ->
        decode_base64_body(data)

      %{"parts" => parts} when is_list(parts) ->
        parts
        |> Enum.map(&extract_part_text/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      _ ->
        ""
    end
  end

  def extract_text_content(_), do: ""

  @doc """
  Extracts email headers (subject, from, to, date) from a message.

  ## Examples

      iex> message = %{payload: %{headers: [%{name: "Subject", value: "Test"}]}}
      iex> GmailClient.extract_headers(message)
      %{subject: "Test", from: nil, to: nil, date: nil}
  """
  @spec extract_headers(message()) :: %{
          subject: String.t() | nil,
          from: String.t() | nil,
          to: String.t() | nil,
          date: String.t() | nil
        }
  def extract_headers(%{"payload" => %{"headers" => headers}}) when is_list(headers) do
    headers_map =
      headers
      |> Enum.reduce(%{}, fn %{"name" => name, "value" => value}, acc ->
        Map.put(acc, String.downcase(name), value)
      end)

    %{
      subject: Map.get(headers_map, "subject"),
      from: Map.get(headers_map, "from"),
      to: Map.get(headers_map, "to"),
      date: Map.get(headers_map, "date")
    }
  end

  def extract_headers(_), do: %{subject: nil, from: nil, to: nil, date: nil}

  # Private functions

  defp extract_part_text(%{"mimeType" => "text/plain", "body" => %{"data" => data}})
       when is_binary(data) and data != "" do
    decode_base64_body(data)
  end

  defp extract_part_text(%{"mimeType" => "text/html", "body" => %{"data" => data}})
       when is_binary(data) and data != "" do
    # For HTML parts, we decode but could add HTML stripping later if needed
    decode_base64_body(data)
  end

  defp extract_part_text(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.map(&extract_part_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp extract_part_text(_), do: nil

  defp decode_base64_body(encoded_data) do
    # Gmail uses URL-safe base64 encoding without padding
    encoded_data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
  rescue
    _ -> ""
  end

  defp to_camel_case(:max_results), do: "maxResults"
  defp to_camel_case(:page_token), do: "pageToken"
  defp to_camel_case(:q), do: "q"
  defp to_camel_case(atom), do: Atom.to_string(atom)
end
