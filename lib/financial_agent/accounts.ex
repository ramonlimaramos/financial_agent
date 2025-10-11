defmodule FinancialAgent.Accounts do
  @moduledoc """
  The Accounts context for managing users and credentials.
  """

  import Ecto.Query, warn: false
  alias FinancialAgent.Repo
  alias FinancialAgent.Accounts.{User, Credential}

  @doc """
  Gets or creates a user by email.

  ## Examples

      iex> get_or_create_user("user@example.com")
      {:ok, %User{}}
  """
  @spec get_or_create_user(String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_user(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> create_user(%{email: email})
      user -> {:ok, user}
    end
  end

  @doc """
  Gets a user by email.

  Returns nil if no user exists.
  """
  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by ID.

  Returns nil if no user exists.
  """
  @spec get_user(Ecto.UUID.t()) :: User.t() | nil
  def get_user(id) do
    Repo.get(User, id)
  end

  @doc """
  Creates a user.
  """
  @spec create_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Stores or updates OAuth credentials for a user.

  ## Examples

      iex> store_credential(user, %{
      ...>   provider: "google",
      ...>   access_token: "token",
      ...>   refresh_token: "refresh",
      ...>   expires_at: ~U[2024-12-31 23:59:59Z]
      ...> })
      {:ok, %Credential{}}
  """
  @spec store_credential(User.t(), map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def store_credential(%User{id: user_id}, attrs) do
    attrs = Map.put(attrs, :user_id, user_id)

    case get_credential(user_id, attrs.provider) do
      nil -> create_credential(attrs)
      credential -> update_credential(credential, attrs)
    end
  end

  @doc """
  Gets a credential for a user and provider.
  """
  @spec get_credential(Ecto.UUID.t(), String.t()) :: Credential.t() | nil
  def get_credential(user_id, provider) when is_binary(provider) do
    Repo.get_by(Credential, user_id: user_id, provider: provider)
  end

  @doc """
  Gets all credentials for a user.
  """
  @spec list_credentials(Ecto.UUID.t()) :: [Credential.t()]
  def list_credentials(user_id) do
    Credential
    |> where([c], c.user_id == ^user_id)
    |> Repo.all()
  end

  @doc """
  Creates a credential.
  """
  @spec create_credential(map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def create_credential(attrs \\ %{}) do
    %Credential{}
    |> Credential.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a credential.
  """
  @spec update_credential(Credential.t(), map()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def update_credential(%Credential{} = credential, attrs) do
    credential
    |> Credential.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a credential.
  """
  @spec delete_credential(Credential.t()) :: {:ok, Credential.t()} | {:error, Ecto.Changeset.t()}
  def delete_credential(%Credential{} = credential) do
    Repo.delete(credential)
  end

  @doc """
  Returns true if a credential is expired or needs refresh.
  """
  @spec credential_expired?(Credential.t()) :: boolean()
  def credential_expired?(%Credential{} = credential) do
    Credential.expired?(credential)
  end

  @doc """
  Preloads credentials for a user.
  """
  @spec preload_credentials(User.t()) :: User.t()
  def preload_credentials(%User{} = user) do
    Repo.preload(user, :credentials)
  end
end
