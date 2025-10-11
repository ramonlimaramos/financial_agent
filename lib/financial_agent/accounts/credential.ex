defmodule FinancialAgent.Accounts.Credential do
  @moduledoc """
  Credential schema for storing encrypted OAuth tokens.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type provider :: :google | :hubspot
  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          user_id: Ecto.UUID.t(),
          provider: String.t(),
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          expires_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credentials" do
    field :provider, :string
    field :access_token, FinancialAgent.Encrypted.Binary, source: :access_token_hash
    field :refresh_token, FinancialAgent.Encrypted.Binary, source: :refresh_token_hash
    field :expires_at, :utc_datetime

    belongs_to :user, FinancialAgent.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a credential.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:user_id, :provider, :access_token, :refresh_token, :expires_at])
    |> validate_required([:user_id, :provider, :access_token])
    |> validate_inclusion(:provider, ["google", "hubspot"])
    |> unique_constraint([:user_id, :provider])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns true if the credential is expired or will expire soon.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end
end
