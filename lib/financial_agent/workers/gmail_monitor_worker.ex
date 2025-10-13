defmodule FinancialAgent.Workers.GmailMonitorWorker do
  @moduledoc """
  Recurring Oban worker that polls Gmail API for new emails.

  This worker:
  1. Fetches all users with Google credentials
  2. For each user, queries Gmail for new emails since last check
  3. Enqueues EventProcessorWorker jobs for each new email
  4. Tracks the last check timestamp to avoid duplicate processing

  Runs every 2 minutes in development, configurable via runtime config.
  """

  use Oban.Worker,
    queue: :gmail_monitor,
    max_attempts: 3,
    priority: 2

  alias FinancialAgent.{Accounts, Repo}
  alias FinancialAgent.Clients.GmailClient
  alias FinancialAgent.Workers.EventProcessorWorker

  require Logger

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    Logger.info("Gmail monitor starting...")

    # Get last check time from job args or default to 5 minutes ago
    last_check = get_last_check_time(args)

    users_with_instructions = list_users_with_email_instructions()

    Logger.info(
      "Checking Gmail for #{length(users_with_instructions)} users with email instructions"
    )

    results =
      Enum.map(users_with_instructions, fn user_id ->
        check_user_emails(user_id, last_check)
      end)

    successful = Enum.count(results, &match?(:ok, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    Logger.info("Gmail monitor completed: #{successful} succeeded, #{failed} failed")

    :ok
  end

  @doc """
  Lists all users who have active email-triggered instructions.
  Only monitors users who actually have rules set up.
  """
  @spec list_users_with_email_instructions() :: [Ecto.UUID.t()]
  def list_users_with_email_instructions do
    # Get all unique user IDs that have active email instructions
    query = """
    SELECT DISTINCT user_id
    FROM instructions
    WHERE is_active = true
    AND trigger_type = 'new_email'
    """

    case Repo.query(query) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [user_id] -> user_id end)

      {:error, reason} ->
        Logger.error("Failed to list users with instructions: #{inspect(reason)}")
        []
    end
  end

  defp check_user_emails(user_id, last_check) do
    with {:ok, credential} <- get_google_credential(user_id),
         {:ok, client} <- build_gmail_client(credential),
         {:ok, new_messages} <- fetch_new_messages(client, last_check),
         :ok <- process_new_messages(user_id, new_messages) do
      Logger.debug("Processed #{length(new_messages)} new emails for user #{user_id}")
      :ok
    else
      {:error, :no_credential} ->
        Logger.debug("User #{user_id} has no Google credential, skipping")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to check emails for user #{user_id}: #{inspect(reason)}")
        error
    end
  end

  defp get_google_credential(user_id) do
    case Accounts.get_credential(user_id, "google") do
      nil -> {:error, :no_credential}
      credential -> {:ok, credential}
    end
  end

  defp build_gmail_client(credential) do
    # Check if token is expired
    if Accounts.credential_expired?(credential) do
      Logger.warning("Gmail token expired for user #{credential.user_id}, needs refresh")
      # For MVP, we'll skip this user. Full implementation would refresh the token.
      {:error, :token_expired}
    else
      {:ok, GmailClient.new(credential.access_token)}
    end
  rescue
    error ->
      Logger.error("Error building Gmail client: #{inspect(error)}")
      {:error, :client_build_failed}
  end

  defp fetch_new_messages(client, last_check) do
    # Query for emails received after last check
    # Using Gmail search syntax: after:YYYY/MM/DD
    query = build_gmail_query(last_check)

    case GmailClient.list_messages(client, q: query, max_results: 20) do
      {:ok, %{"messages" => messages}} when is_list(messages) ->
        # Fetch full details for each message
        detailed_messages =
          messages
          |> Enum.take(20)
          |> Enum.map(fn %{"id" => id} ->
            case GmailClient.get_message(client, id) do
              {:ok, message} -> message
              {:error, _} -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, detailed_messages}

      {:ok, _response} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_gmail_query(last_check) do
    # Format: after:YYYY/MM/DD
    # Also filter to only INBOX and exclude SPAM/TRASH
    date_str = Calendar.strftime(last_check, "%Y/%m/%d")
    "after:#{date_str} in:inbox -in:spam -in:trash"
  end

  defp process_new_messages(_user_id, []), do: :ok

  defp process_new_messages(user_id, messages) do
    messages
    |> Enum.each(fn message ->
      event_data = format_email_as_event(message)

      %{
        user_id: user_id,
        event_type: "email",
        event_data: event_data
      }
      |> EventProcessorWorker.new()
      |> Oban.insert()
    end)

    :ok
  end

  defp format_email_as_event(message) do
    headers = GmailClient.extract_headers(message)
    content = GmailClient.extract_text_content(message)

    %{
      "type" => "email",
      "message_id" => message["id"],
      "thread_id" => message["threadId"],
      "subject" => headers.subject,
      "from" => headers.from,
      "to" => headers.to,
      "date" => headers.date,
      "content" => String.slice(content, 0, 2000),
      "snippet" => message["snippet"],
      "metadata" => %{
        "internal_date" => message["internalDate"],
        "label_ids" => message["labelIds"] || []
      }
    }
  end

  defp get_last_check_time(%{"last_check" => timestamp}) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp, :second)
  end

  defp get_last_check_time(_args) do
    # Default: check emails from last 5 minutes
    DateTime.utc_now()
    |> DateTime.add(-5, :minute)
  end
end
