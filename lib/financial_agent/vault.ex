defmodule FinancialAgent.Vault do
  @moduledoc """
  Cloak Vault for encrypting sensitive data like OAuth tokens.
  """

  use Cloak.Vault, otp_app: :financial_agent

  def init(config) do
    config =
      Keyword.put(config, :ciphers,
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: "AES.GCM.V1", key: get_key!()
        }
      )

    {:ok, config}
  end

  defp get_key! do
    case System.get_env("CLOAK_KEY") do
      nil ->
        raise ArgumentError, """
        Environment variable CLOAK_KEY is missing.
        Generate a key with: mix phx.gen.secret 32
        """

      key ->
        Base.decode64!(key)
    end
  end
end
