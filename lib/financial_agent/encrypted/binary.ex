defmodule FinancialAgent.Encrypted.Binary do
  @moduledoc """
  Custom Ecto type for encrypted string fields using Cloak.

  This type encrypts strings to binary and decrypts binary to strings.
  """

  use Cloak.Ecto.Binary, vault: FinancialAgent.Vault

  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}
  def cast(_), do: :error

  def dump(value) when is_binary(value) do
    {:ok, FinancialAgent.Vault.encrypt!(value)}
  end

  def dump(nil), do: {:ok, nil}
  def dump(_), do: :error

  def load(value) when is_binary(value) do
    {:ok, FinancialAgent.Vault.decrypt!(value)}
  end

  def load(nil), do: {:ok, nil}
  def load(_), do: :error
end
