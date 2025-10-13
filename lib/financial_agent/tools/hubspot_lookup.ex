defmodule FinancialAgent.Tools.HubspotLookup do
  @moduledoc """
  Tool for looking up contact information from HubSpot CRM.
  """

  alias FinancialAgent.Clients.HubSpotClient
  alias FinancialAgent.Accounts

  @doc """
  Looks up a HubSpot contact by name.

  Returns contact information including email, phone, and recent notes.
  """
  @spec call(String.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, term()}
  def call(contact_name, user_id) do
    with {:ok, credential} <- get_hubspot_credential(user_id),
         client <- build_client(credential),
         {:ok, results} <- search_by_name(client, contact_name),
         {:ok, contact_info} <- format_contact_info(results) do
      {:ok, contact_info}
    end
  end

  defp get_hubspot_credential(user_id) do
    case Accounts.get_credential(user_id, "hubspot") do
      nil -> {:error, :hubspot_not_connected}
      credential -> {:ok, credential}
    end
  end

  defp build_client(credential) do
    HubSpotClient.new(credential.access_token)
  end

  defp search_by_name(client, contact_name) do
    search_request = %{
      filterGroups: [
        %{
          filters: [
            %{
              propertyName: "firstname",
              operator: "CONTAINS_TOKEN",
              value: contact_name
            }
          ]
        },
        %{
          filters: [
            %{
              propertyName: "lastname",
              operator: "CONTAINS_TOKEN",
              value: contact_name
            }
          ]
        }
      ]
    }

    case HubSpotClient.search_contacts(client, search_request) do
      {:ok, %{"results" => results}} -> {:ok, results}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_contact_info([]), do: {:error, :contact_not_found}

  defp format_contact_info(contacts) when is_list(contacts) do
    primary_contact = List.first(contacts)

    contact_data = %{
      name:
        get_property(primary_contact, "firstname") <>
          " " <> get_property(primary_contact, "lastname"),
      email: get_property(primary_contact, "email"),
      phone: get_property(primary_contact, "phone"),
      company: get_property(primary_contact, "company"),
      job_title: get_property(primary_contact, "jobtitle"),
      total_results: length(contacts)
    }

    {:ok, contact_data}
  end

  defp get_property(contact, property_name) do
    get_in(contact, ["properties", property_name]) || "N/A"
  end
end
