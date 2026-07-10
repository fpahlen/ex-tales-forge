defmodule TalesForge.Images do
  @moduledoc """
  Image enqueue + helpers for scenes (depict narrative text).

  - Uses prompt-to-image (e.g. pollinations) so generated images match the scene description.
  - Never uses non-descriptive placeholders like picsum.
  """

  alias TalesForge.Workers.GenerateImage

  alias TalesForge.Workers.GenerateImage

  def enqueue_portrait(npc_definition_id, opts \\ []) do
    %{type: :portrait, target_id: npc_definition_id, opts: opts}
    |> GenerateImage.new(queue: :images)
    |> Oban.insert()
  end

  def enqueue_scene_image(location_id, opts \\ []) do
    # opts can include :session_id, :narrative (preferred for fresh scene), :location_name
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

  # Fallback only if generation fails
  def fallback_image_url,
    do: "https://image.pollinations.ai/prompt/generic%20fantasy%20scene?width=800&height=600"
end
