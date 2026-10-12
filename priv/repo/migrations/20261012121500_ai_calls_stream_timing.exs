defmodule TalesForge.Repo.Migrations.AiCallsStreamTiming do
  use Ecto.Migration

  # Add-only. ttft_ms: time to the first streamed token of one request.
  # narration_variant: the GM reply variant ("full" or "lean").
  def change do
    alter table(:ai_calls) do
      add :ttft_ms, :integer
      add :narration_variant, :string
    end
  end
end
