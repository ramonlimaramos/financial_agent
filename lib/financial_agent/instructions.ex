defmodule FinancialAgent.Instructions do
  @moduledoc """
  Context for managing user instructions that trigger automatically on events.
  """

  import Ecto.Query
  alias FinancialAgent.Instructions.Instruction
  alias FinancialAgent.Repo

  @doc """
  Creates a new instruction for a user.

  ## Examples

      iex> create_instruction(%{user_id: user_id, trigger_type: "new_email", ...})
      {:ok, %Instruction{}}

      iex> create_instruction(%{invalid: "data"})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_instruction(map()) :: {:ok, Instruction.t()} | {:error, Ecto.Changeset.t()}
  def create_instruction(attrs) do
    %Instruction{}
    |> Instruction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an existing instruction.
  """
  @spec update_instruction(Instruction.t(), map()) ::
          {:ok, Instruction.t()} | {:error, Ecto.Changeset.t()}
  def update_instruction(%Instruction{} = instruction, attrs) do
    instruction
    |> Instruction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an instruction.
  """
  @spec delete_instruction(Instruction.t()) ::
          {:ok, Instruction.t()} | {:error, Ecto.Changeset.t()}
  def delete_instruction(%Instruction{} = instruction) do
    Repo.delete(instruction)
  end

  @doc """
  Gets a single instruction by ID.

  Returns `{:ok, instruction}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_instruction(Ecto.UUID.t()) :: {:ok, Instruction.t()} | {:error, :not_found}
  def get_instruction(id) do
    case Repo.get(Instruction, id) do
      nil -> {:error, :not_found}
      instruction -> {:ok, instruction}
    end
  end

  @doc """
  Gets a single instruction by ID, raising if not found.
  """
  @spec get_instruction!(Ecto.UUID.t()) :: Instruction.t()
  def get_instruction!(id), do: Repo.get!(Instruction, id)

  @doc """
  Lists all instructions for a user.
  """
  @spec list_instructions(Ecto.UUID.t()) :: [Instruction.t()]
  def list_instructions(user_id) do
    Instruction
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Lists all active instructions for a user, optionally filtered by trigger type.

  ## Examples

      iex> list_active_instructions(user_id)
      [%Instruction{is_active: true}, ...]

      iex> list_active_instructions(user_id, "new_email")
      [%Instruction{is_active: true, trigger_type: "new_email"}, ...]
  """
  @spec list_active_instructions(Ecto.UUID.t(), String.t() | nil) :: [Instruction.t()]
  def list_active_instructions(user_id, trigger_type \\ nil) do
    query =
      Instruction
      |> where([i], i.user_id == ^user_id and i.is_active == true)

    query =
      if trigger_type do
        where(query, [i], i.trigger_type == ^trigger_type)
      else
        query
      end

    query
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @doc """
  Toggles the is_active status of an instruction.

  ## Examples

      iex> toggle_instruction(%Instruction{is_active: true})
      {:ok, %Instruction{is_active: false}}
  """
  @spec toggle_instruction(Instruction.t()) ::
          {:ok, Instruction.t()} | {:error, Ecto.Changeset.t()}
  def toggle_instruction(%Instruction{} = instruction) do
    update_instruction(instruction, %{is_active: !instruction.is_active})
  end

  @doc """
  Checks if a user has any active instructions for a given trigger type.
  """
  @spec has_active_instructions?(Ecto.UUID.t(), String.t()) :: boolean()
  def has_active_instructions?(user_id, trigger_type) do
    Instruction
    |> where([i], i.user_id == ^user_id)
    |> where([i], i.trigger_type == ^trigger_type)
    |> where([i], i.is_active == true)
    |> Repo.exists?()
  end
end
