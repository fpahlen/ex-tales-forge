defmodule TalesForge.Images do
  @moduledoc """
  Phase 2 stub for Tigris image storage + generation.

  - Enqueues work on the existing "images" Oban queue.
  - Will handle portrait generation (NPC/Roster) and scene images.
  - For now: accepts a target (npc_id or location), queues a no-op job that
    can later call xAI/Grok image APIs + upload to Tigris and patch the
    Ash resource (portrait_url / scene_image_url).

  Config comes from env (see .env.example): AWS_* for Tigris S3 compat.
  """

  def enqueue_portrait(npc_definition_id, opts \\ []) do
    %{type: :portrait, target_id: npc_definition_id, opts: opts}
    |> TalesForge.Workers.GenerateImage.new(queue: :images)
    |> Oban.insert()
  end

  def enqueue_scene_image(location_id, session_id \\ nil) do
    %{type: :scene, target_id: location_id, session_id: session_id}
    |> TalesForge.Workers.GenerateImage.new(queue: :images)
    |> Oban.insert()
  end

  # Future: actual upload using Req or ExAws + Tigris creds.
  # For dev: return a placeholder or local path.
  def public_url(_key), do: nil
end
