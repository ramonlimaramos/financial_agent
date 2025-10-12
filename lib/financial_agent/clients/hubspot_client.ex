defmodule FinancialAgent.Clients.HubSpotClient do
  @moduledoc """
  Tesla-based HTTP client for interacting with HubSpot API.

  Handles authentication, rate limiting, and common HubSpot operations
  like fetching contacts and company data.
  """

  use Tesla

  require Logger

  @base_url "https://api.hubapi.com"

  @type contact_list_opts :: [
          limit: pos_integer(),
          after: String.t(),
          properties: [String.t()],
          associations: [String.t()]
        ]

  @type contact :: %{
          id: String.t(),
          properties: map(),
          created_at: String.t(),
          updated_at: String.t(),
          archived: boolean()
        }

  @doc """
  Creates a new HubSpot client with the provided access token.

  Supports both Private App tokens (Bearer) and Developer API Keys (hapikey).
  Automatically detects which authentication method to use based on token format.

  ## Examples

      iex> client = HubSpotClient.new("access_token_here")
      iex> client = HubSpotClient.new("developer_api_key_here", auth_type: :hapikey)
  """
  @spec new(String.t(), keyword()) :: Tesla.Client.t()
  def new(access_token, opts \\ []) do
    auth_type = Keyword.get(opts, :auth_type, detect_auth_type(access_token))

    middleware = [
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry,
       delay: 1000,
       max_retries: 3,
       max_delay: 10_000,
       should_retry: fn
         {:ok, %{status: status}} when status in [429, 500, 502, 503] -> true
         {:ok, _} -> false
         {:error, _} -> true
       end}
    ]

    middleware =
      case auth_type do
        :bearer ->
          [
            {Tesla.Middleware.Headers, [{"authorization", "Bearer #{access_token}"}]}
            | middleware
          ]

        :hapikey ->
          [
            {Tesla.Middleware.Query, [hapikey: access_token]}
            | middleware
          ]
      end

    Tesla.client(middleware)
  end

  # Detects authentication type based on token format
  # Private App tokens are typically longer and contain specific patterns
  # Developer API Keys are usually 36-40 characters UUID-like format
  defp detect_auth_type(token) when byte_size(token) < 50, do: :hapikey
  defp detect_auth_type(_token), do: :bearer

  @doc """
  Lists contacts from HubSpot CRM.

  Uses v1 API for compatibility with Developer API Keys.

  ## Options

    * `:count` - Maximum number of contacts to return (default: 100, max: 100)
    * `:vidOffset` - Pagination offset (contact ID to start from)
    * `:property` - List of contact properties to return

  ## Examples

      iex> client = HubSpotClient.new(token)
      iex> HubSpotClient.list_contacts(client, count: 50)
      {:ok, %{contacts: [...], "has-more" => true}}
  """
  @spec list_contacts(Tesla.Client.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def list_contacts(client, opts \\ []) do
    count = Keyword.get(opts, :count, 100)
    vid_offset = Keyword.get(opts, :vidOffset)
    properties = Keyword.get(opts, :property, [])

    query_params =
      [count: count]
      |> maybe_add_param(:vidOffset, vid_offset)
      |> maybe_add_list_param(:property, properties)

    # Use v1 API which works with Developer API Keys
    case Tesla.get(client, "/contacts/v1/lists/all/contacts/all", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("HubSpot API list_contacts error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("HubSpot API list_contacts network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Gets a specific contact by ID.

  ## Options

    * `:properties` - List of contact properties to return
    * `:associations` - List of associated objects to include

  ## Examples

      iex> client = HubSpotClient.new(token)
      iex> HubSpotClient.get_contact(client, "12345")
      {:ok, %{id: "12345", properties: %{...}}}
  """
  @spec get_contact(Tesla.Client.t(), String.t(), keyword()) ::
          {:ok, contact()} | {:error, term()}
  def get_contact(client, contact_id, opts \\ []) do
    properties = Keyword.get(opts, :properties, [])
    associations = Keyword.get(opts, :associations, [])

    query_params =
      []
      |> maybe_add_list_param(:properties, properties)
      |> maybe_add_list_param(:associations, associations)

    case Tesla.get(client, "/crm/v3/objects/contacts/#{contact_id}", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 404}} ->
        {:error, :not_found}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("HubSpot API get_contact error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("HubSpot API get_contact network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Searches contacts using HubSpot's search API.

  ## Examples

      iex> client = HubSpotClient.new(token)
      iex> filter = %{
      ...>   filterGroups: [
      ...>     %{
      ...>       filters: [
      ...>         %{propertyName: "email", operator: "CONTAINS", value: "@example.com"}
      ...>       ]
      ...>     }
      ...>   ]
      ...> }
      iex> HubSpotClient.search_contacts(client, filter)
      {:ok, %{results: [...]}}
  """
  @spec search_contacts(Tesla.Client.t(), map()) :: {:ok, map()} | {:error, term()}
  def search_contacts(client, search_request) do
    case Tesla.post(client, "/crm/v3/objects/contacts/search", search_request) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("HubSpot API search_contacts error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("HubSpot API search_contacts network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists companies from HubSpot CRM.

  Similar to list_contacts but for company objects.

  ## Examples

      iex> client = HubSpotClient.new(token)
      iex> HubSpotClient.list_companies(client, limit: 50)
      {:ok, %{results: [...]}}
  """
  @spec list_companies(Tesla.Client.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_companies(client, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    after_cursor = Keyword.get(opts, :after)
    properties = Keyword.get(opts, :properties, [])

    query_params =
      [limit: limit]
      |> maybe_add_param(:after, after_cursor)
      |> maybe_add_list_param(:properties, properties)

    case Tesla.get(client, "/crm/v3/objects/companies", query: query_params) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.error("HubSpot API list_companies error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body}}

      {:error, reason} = error ->
        Logger.error("HubSpot API list_companies network error: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Extracts key contact information into a simplified format.

  ## Examples

      iex> contact = %{"properties" => %{"firstname" => "John", "lastname" => "Doe", "email" => "john@example.com"}}
      iex> HubSpotClient.extract_contact_info(contact)
      %{firstname: "John", lastname: "Doe", email: "john@example.com", ...}
  """
  @spec extract_contact_info(contact()) :: map()
  def extract_contact_info(%{"properties" => properties}) when is_map(properties) do
    %{
      firstname: Map.get(properties, "firstname"),
      lastname: Map.get(properties, "lastname"),
      email: Map.get(properties, "email"),
      phone: Map.get(properties, "phone"),
      company: Map.get(properties, "company"),
      jobtitle: Map.get(properties, "jobtitle"),
      lifecyclestage: Map.get(properties, "lifecyclestage"),
      hs_lead_status: Map.get(properties, "hs_lead_status")
    }
  end

  def extract_contact_info(_), do: %{}

  @doc """
  Formats contact data as searchable text for RAG ingestion.

  ## Examples

      iex> contact = %{"properties" => %{"firstname" => "John", "lastname" => "Doe"}}
      iex> HubSpotClient.format_contact_text(contact)
      "Contact: John Doe\\nEmail: \\nCompany: \\n..."
  """
  @spec format_contact_text(contact()) :: String.t()
  def format_contact_text(contact) do
    info = extract_contact_info(contact)

    """
    Contact: #{format_name(info)}
    Email: #{info.email || "N/A"}
    Company: #{info.company || "N/A"}
    Job Title: #{info.jobtitle || "N/A"}
    Phone: #{info.phone || "N/A"}
    Lifecycle Stage: #{info.lifecyclestage || "N/A"}
    Lead Status: #{info.hs_lead_status || "N/A"}
    """
    |> String.trim()
  end

  # Private functions

  defp format_name(%{firstname: first, lastname: last})
       when is_binary(first) and is_binary(last) do
    "#{first} #{last}"
  end

  defp format_name(%{firstname: first}) when is_binary(first), do: first
  defp format_name(%{lastname: last}) when is_binary(last), do: last
  defp format_name(_), do: "Unknown"

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Keyword.put(params, key, value)

  defp maybe_add_list_param(params, _key, []), do: params

  defp maybe_add_list_param(params, key, values) when is_list(values) do
    Enum.reduce(values, params, fn value, acc ->
      Keyword.put(acc, key, value)
    end)
  end
end
