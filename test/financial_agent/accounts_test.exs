defmodule FinancialAgent.AccountsTest do
  use FinancialAgent.DataCase

  import FinancialAgent.Factory

  alias FinancialAgent.Accounts

  describe "users" do
    test "get_or_create_user/1 creates a new user when email doesn't exist" do
      email = "newuser@example.com"

      assert {:ok, user} = Accounts.get_or_create_user(email)
      assert user.email == email
      assert user.id
    end

    test "get_or_create_user/1 returns existing user when email exists" do
      existing_user = insert(:user, email: "existing@example.com")

      assert {:ok, user} = Accounts.get_or_create_user("existing@example.com")
      assert user.id == existing_user.id
      assert user.email == existing_user.email
    end

    test "get_user/1 returns user by id" do
      user = insert(:user)

      assert retrieved_user = Accounts.get_user(user.id)
      assert retrieved_user.id == user.id
      assert retrieved_user.email == user.email
    end

    test "get_user/1 returns nil when user doesn't exist" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end
  end

  describe "credentials" do
    test "store_credential/2 creates a new credential for user" do
      user = insert(:user)

      attrs = %{
        provider: "google",
        access_token: "test_token",
        refresh_token: "test_refresh",
        expires_at: DateTime.utc_now() |> DateTime.add(3600, :second)
      }

      assert {:ok, credential} = Accounts.store_credential(user, attrs)
      assert credential.user_id == user.id
      assert credential.provider == "google"
      assert credential.access_token == "test_token"
      assert credential.refresh_token == "test_refresh"
    end

    test "store_credential/2 updates existing credential for same provider" do
      user = insert(:user)
      insert(:credential, user: user, provider: "google", access_token: "old_token")

      attrs = %{
        provider: "google",
        access_token: "new_token",
        refresh_token: "new_refresh"
      }

      assert {:ok, credential} = Accounts.store_credential(user, attrs)
      assert credential.access_token == "new_token"
      assert credential.refresh_token == "new_refresh"

      # Verify only one credential exists
      credentials = Accounts.list_credentials(user.id)
      assert length(credentials) == 1
    end

    test "get_credential/2 returns credential by provider" do
      user = insert(:user)
      credential = insert(:credential, user: user, provider: "google")

      assert retrieved = Accounts.get_credential(user.id, "google")
      assert retrieved.id == credential.id
      assert retrieved.provider == "google"
    end

    test "get_credential/2 returns nil when credential doesn't exist" do
      user = insert(:user)

      assert Accounts.get_credential(user.id, "hubspot") == nil
    end

    test "list_credentials/1 returns all credentials for user" do
      user = insert(:user)
      google_cred = insert(:credential, user: user, provider: "google")
      hubspot_cred = insert(:credential, user: user, provider: "hubspot")

      # Create credential for different user (should not be returned)
      other_user = insert(:user)
      insert(:credential, user: other_user, provider: "google")

      credentials = Accounts.list_credentials(user.id)
      assert length(credentials) == 2
      assert Enum.any?(credentials, &(&1.id == google_cred.id))
      assert Enum.any?(credentials, &(&1.id == hubspot_cred.id))
    end

    test "credentials are encrypted in the database" do
      user = insert(:user)

      attrs = %{
        provider: "google",
        access_token: "my_secret_token",
        refresh_token: "my_secret_refresh"
      }

      {:ok, credential} = Accounts.store_credential(user, attrs)

      # Query the database using Ecto.Query with raw SQL to bypass decryption
      query = """
      SELECT access_token_hash, refresh_token_hash
      FROM credentials
      WHERE id = $1::uuid
      """

      # Convert UUID to binary format for PostgreSQL
      {:ok, uuid_binary} = Ecto.UUID.dump(credential.id)
      result = Ecto.Adapters.SQL.query!(Repo, query, [uuid_binary])
      [[access_token_hash, refresh_token_hash]] = result.rows

      # The hash fields should not contain the plain text
      refute access_token_hash =~ "my_secret_token"
      refute refresh_token_hash =~ "my_secret_refresh"

      # But the struct should have decrypted values
      assert credential.access_token == "my_secret_token"
      assert credential.refresh_token == "my_secret_refresh"
    end
  end
end
