defmodule FinancialAgent.OAuth.HubSpot do
  @moduledoc """
  HubSpot OAuth 2.0 client implementation.

  Since there's no official Ueberauth strategy for HubSpot,
  this module provides direct OAuth 2.0 integration.
  """

  @authorize_url "https://app.hubspot.com/oauth/authorize"
  @token_url "https://api.hubapi.com/oauth/v1/token"
  @scopes [
    "crm.objects.contacts.read",
    "crm.objects.contacts.write",
    "crm.objects.companies.read",
    "crm.objects.deals.read"
  ]

  @doc """
  Generates the OAuth authorization URL to redirect users to HubSpot.

  ## Parameters
    - redirect_uri: The callback URL registered in your HubSpot app
    - state: CSRF token for security (optional but recommended)

  ## Examples

      iex> HubSpot.authorize_url("http://localhost:4000/auth/hubspot/callback", "random_state")
      "https://app.hubspot.com/oauth/authorize?client_id=...&redirect_uri=...&scope=..."
  """
  def authorize_url(redirect_uri, state \\ nil) do
    client_id = get_client_id!()
    scope = Enum.join(@scopes, " ")

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: scope
    }

    params = if state, do: Map.put(params, :state, state), else: params

    query_string = URI.encode_query(params)
    "#{@authorize_url}?#{query_string}"
  end

  @doc """
  Exchanges an authorization code for an access token.

  ## Parameters
    - code: The authorization code from HubSpot callback
    - redirect_uri: The same redirect URI used in authorization

  ## Returns
    - {:ok, token_response} on success
    - {:error, reason} on failure

  Token response includes:
    - access_token
    - refresh_token
    - expires_in
  """
  def get_token(code, redirect_uri) do
    client_id = get_client_id!()
    client_secret = get_client_secret!()

    body = %{
      grant_type: "authorization_code",
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      code: code
    }

    case HTTPoison.post(@token_url, Jason.encode!(body), [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes an expired access token using a refresh token.

  ## Parameters
    - refresh_token: The refresh token from previous authorization

  ## Returns
    - {:ok, token_response} with new access_token
    - {:error, reason} on failure
  """
  def refresh_token(refresh_token) do
    client_id = get_client_id!()
    client_secret = get_client_secret!()

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token
    }

    case HTTPoison.post(@token_url, Jason.encode!(body), [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200, body: response_body}} ->
        {:ok, Jason.decode!(response_body)}

      {:ok, %{status_code: status, body: response_body}} ->
        {:error, {:http_error, status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_client_id! do
    System.get_env("HUBSPOT_CLIENT_ID") ||
      raise "HUBSPOT_CLIENT_ID environment variable is not set"
  end

  defp get_client_secret! do
    System.get_env("HUBSPOT_CLIENT_SECRET") ||
      raise "HUBSPOT_CLIENT_SECRET environment variable is not set"
  end
end
