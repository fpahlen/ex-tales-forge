defmodule ExTalesForge.Repo.Migrations.ChangeScenesImageUrlToText do
  use Ecto.Migration

  def change do
    alter table(:scenes) do
      modify :image_url, :text
    end
  end
end
