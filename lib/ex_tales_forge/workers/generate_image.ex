defmodule TalesForge.Workers.GenerateImage do
  @moduledoc """
  Oban worker for image generation + Tigris upload.

  For scenes:
  - Builds rich prompt from the full narrative text + location.
  - Generates image URL using prompt-to-image service (pollinations/flux) so it depicts the scene in the text.
  - (Future: download + upload to Tigris if configured for permanent hosting.)
  - Updates runtime Scene.image_url (Ecto).
  - Broadcasts {:scene_image_ready, ...} for PlayLive.

  Authored images (from pack Locations) take precedence and are never overwritten by gen.
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 3

  require Logger
  import Ecto.Query

  alias TalesForge.Images
  alias TalesForge.Repo
  alias TalesForge.Schemas.Scene

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    type = Map.get(args, "type") || Map.get(args, :type)
    target_id = Map.get(args, "target_id") || Map.get(args, :target_id)

    Logger.info("GenerateImage starting type=#{type} target=#{target_id}")

    case type do
      "scene" ->
        generate_scene_image(args)

      :scene ->
        generate_scene_image(args)

      _ ->
        Logger.info("GenerateImage: unknown type #{type}")
        :ok
    end
  end

  defp generate_scene_image(args) do
    location_id = Map.get(args, "target_id") || Map.get(args, :target_id)
    session_id = Map.get(args, "session_id") || Map.get(args, :session_id)
    narrative = Map.get(args, "narrative") || Map.get(args, :narrative) || ""
    location_name = Map.get(args, "location_name") || Map.get(args, :location_name) || location_id

    prompt = build_scene_prompt(location_name, narrative)

    generated_url = generate_image_bytes(prompt)

    # In real impl with Tigris + real gen, we would upload bytes here and get back a durable URL.
    # For now we use the public generated URL directly (still goes through worker for future-proofing).
    image_url = generated_url || Images.fallback_image_url()

    if session_id do
      update_scene_image(session_id, location_id, image_url)

      TalesForge.PubSub.GameSession.broadcast(
        session_id,
        {:scene_image_ready,
         %{
           session_id: session_id,
           location_id: location_id,
           image_url: image_url
         }}
      )
    end

    Logger.info("GenerateImage scene done location=#{location_id} url=#{image_url}")
    :ok
  end

  defp build_scene_prompt(location_name, narrative) do
    desc = if narrative != "", do: narrative, else: "atmospheric location"

    "Cinematic, highly detailed digital illustration of the scene: #{desc} at #{location_name}. " <>
      "Fantasy RPG style, dramatic lighting, vivid atmosphere, book cover quality, no text, no watermark"
  end

  # Prompt-based generation using Pollinations (Flux model) so the image depicts the scene narrative text.
  # Returns a direct URL to the generated image. No key needed for basic use.
  # (Later: swap to xAI image endpoint if using XAI_API_KEY for native Grok/Flux gen.)
  defp generate_image_bytes(prompt) do
    encoded = URI.encode(prompt)
    "https://image.pollinations.ai/prompt/#{encoded}?width=800&height=600&model=flux&safe=false"
  end

  defp upload_to_tigris(_bytes, key) do
    # For real Tigris + bytes: download from the gen URL then put to bucket.
    # For now, we return the direct pollinations URL (depicts the prompt text).
    # If Tigris configured in future, we can proxy/upload for persistence.
    if TalesForge.Config.tigris_configured?() do
      Logger.info("Tigris configured but using direct prompt URL for #{key} (depicts narrative).")
    end

    Images.public_url(key) || "https://image.pollinations.ai/prompt/placeholder"
  end

  defp update_scene_image(session_id, location_id, url) do
    Scene
    |> where([s], s.game_session_id == ^session_id and s.location_id == ^location_id)
    |> Repo.update_all(set: [image_url: url])
  end
end
