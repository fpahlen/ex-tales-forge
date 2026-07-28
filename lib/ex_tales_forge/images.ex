defmodule TalesForge.Images do
  @moduledoc """
  Image enqueue + helpers for scenes (narrative) and NPC portraits.

  - Scenes: depict full narrative using Grok/xAI (or fallback) + "pencil sketch by GM on paper" style.
  - Portraits: generated from NPC `appearance` (description) + `personality` (plus name/role).
    Same Grok default + consistent pencil-sketch-GM style.
  - Enqueue only happens when no authored `*_url` is present (authored from packs win).
  - Never uses non-descriptive placeholders like picsum.
  """

  alias TalesForge.Workers.GenerateImage

  def enqueue_portrait(npc_definition_id, opts \\ []) do
    %{type: :portrait, target_id: npc_definition_id, opts: opts}
    |> GenerateImage.new(queue: :images)
    |> Oban.insert()
  end

  def enqueue_scene_image(location_id, opts \\ []) do
    # opts: :session_id, :narrative, :location_name, :npc_refs
    # (npc_refs: list of %{name, appearance, personality, portrait_url})
    args = Map.merge(%{type: :scene, target_id: location_id}, Map.new(opts))

    args
    |> GenerateImage.new(queue: :images)
    |> Oban.insert()
  end

  # Helpers for worker / tests
  def tigris_bucket, do: TalesForge.Config.tigris_bucket()
  def tigris_endpoint, do: TalesForge.Config.tigris_endpoint()

  def public_url(key) do
    base = TalesForge.Config.public_url_base()
    if base != "", do: "#{base}/#{key}", else: "#{tigris_endpoint()}/#{tigris_bucket()}/#{key}"
  end
end
