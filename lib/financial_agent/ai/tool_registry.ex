defmodule FinancialAgent.AI.ToolRegistry do
  @moduledoc """
  Registry of available tools for LLM function calling.
  Defines tool schemas in OpenAI function calling format.
  """

  @doc """
  Returns a list of all available tools in OpenAI function calling format.
  """
  @spec available_tools() :: [map()]
  def available_tools do
    [
      hubspot_contact_lookup_tool()
    ]
  end

  @doc """
  Gets a specific tool definition by name.
  """
  @spec get_tool(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_tool(tool_name) do
    case Enum.find(available_tools(), fn tool ->
           get_in(tool, [:function, :name]) == tool_name
         end) do
      nil -> {:error, :not_found}
      tool -> {:ok, tool}
    end
  end

  defp hubspot_contact_lookup_tool do
    %{
      type: "function",
      function: %{
        name: "get_hubspot_contact",
        description: """
        Looks up detailed contact information from HubSpot CRM.
        Use this when the user asks for contact details, email addresses, phone numbers, or information about a specific person.
        """,
        parameters: %{
          type: "object",
          properties: %{
            name: %{
              type: "string",
              description: "The full or partial name of the contact to search for"
            }
          },
          required: ["name"]
        }
      }
    }
  end
end
