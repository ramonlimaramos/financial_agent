defmodule FinancialAgent.Factory do
  @moduledoc """
  ExMachina factory for generating test data.
  """

  use ExMachina.Ecto, repo: FinancialAgent.Repo

  alias FinancialAgent.Accounts.{User, Credential}
  alias FinancialAgent.RAG.Chunk

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def credential_factory do
    %Credential{
      user: build(:user),
      provider: "google",
      access_token: "test_access_token_#{System.unique_integer([:positive])}",
      refresh_token: "test_refresh_token_#{System.unique_integer([:positive])}",
      expires_at: DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second),
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def google_credential_factory do
    struct!(
      credential_factory(),
      %{provider: "google"}
    )
  end

  def hubspot_credential_factory do
    struct!(
      credential_factory(),
      %{provider: "hubspot"}
    )
  end

  def chunk_factory do
    %Chunk{
      user: build(:user),
      source: "gmail",
      source_id: sequence(:source_id, &"source_id_#{&1}"),
      content: "This is test content for a chunk",
      metadata: %{
        "source" => "gmail",
        "subject" => "Test Subject",
        "from" => "test@example.com"
      },
      embedding: nil,
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  def gmail_chunk_factory do
    struct!(
      chunk_factory(),
      %{
        source: "gmail",
        metadata: %{
          "source" => "gmail",
          "message_id" => sequence(:message_id, &"msg_#{&1}"),
          "thread_id" => sequence(:thread_id, &"thread_#{&1}"),
          "subject" => "Test Email Subject",
          "from" => "sender@example.com",
          "to" => "recipient@example.com",
          "date" => "Mon, 1 Jan 2024 12:00:00 +0000"
        }
      }
    )
  end

  def hubspot_chunk_factory do
    struct!(
      chunk_factory(),
      %{
        source: "hubspot",
        content: "Contact: John Doe\nEmail: john@example.com\nCompany: Acme Inc",
        metadata: %{
          "source" => "hubspot",
          "contact_id" => sequence(:contact_id, &"#{&1}"),
          "email" => "john@example.com",
          "company" => "Acme Inc",
          "name" => "John Doe",
          "lifecycle_stage" => "lead"
        }
      }
    )
  end

  def chunk_with_embedding_factory do
    # Generate a random 1536-dimension vector
    embedding = Enum.map(1..1536, fn _ -> :rand.uniform() * 2 - 1 end)

    struct!(
      chunk_factory(),
      %{embedding: Pgvector.new(embedding)}
    )
  end
end
