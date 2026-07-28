defmodule ExTalesForge.Repo.Migrations.ChangePortraitUrlToText do
  use Ecto.Migration

  def change do
    alter table(:npc_definitions) do
      modify :portrait_url, :text
    end

    alter table(:locations) do
      modify :scene_image_url, :text
    end
  end
end
