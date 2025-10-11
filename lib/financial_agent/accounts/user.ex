defmodule FinancialAgent.Accounts.User do
  @moduledoc """
  User schema for authentication and data ownership.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          email: String.t(),
          credentials: [FinancialAgent.Accounts.Credential.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string

    has_many :credentials, FinancialAgent.Accounts.Credential
    has_many :chunks, FinancialAgent.RAG.Chunk

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new user.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
end
