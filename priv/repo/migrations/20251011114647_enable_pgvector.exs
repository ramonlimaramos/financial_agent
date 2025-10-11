defmodule FinancialAgent.Repo.Migrations.EnablePgvector do
  use Ecto.Migration

  def up do
    # Enable pgvector extension for vector similarity search
    execute "CREATE EXTENSION IF NOT EXISTS vector"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
