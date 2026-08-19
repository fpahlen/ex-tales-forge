defmodule TalesForge.Workers.GenerateImage do
  @moduledoc """
  Oban worker for image generation. Grok/xAI is the default image generator.

  ## Contract

  Job args (string or atom keys; normalized once in `perform/1`):

  - `type` (required): `"scene"` | `"portrait"`
  - `target_id` (required): location_id for scenes, npc_id slug for portraits
  - scene-only: `session_id`, `narrative`, `location_name`, `npc_refs`

  Invalid `type` or missing `target_id` → `{:error, reason}` (fail fast; no silent success).
  Unknown NPC definition for portrait → log + `:ok` (expected when authoring row missing).

  Image style is centralized in `gm_pencil_sketch_style/1` so scenes and portraits
  always use identical "pencil sketch by a very skilled GM on paper" instructions (DRY).

  For scenes:
  - Builds a prompt that renders the narrative as a pencil sketch drawn by a skilled GM on paper.
  - If `:npc_refs` provided, appends character-consistency lines for present NPCs.
  - Calls xAI (Grok) when configured; falls back to pollinations; mock in tests.
  - (Future: download bytes + upload to Tigris for permanent short URLs.)
  - Updates runtime `Scene.image_url` (Ecto) and broadcasts `{:scene_image_ready, ...}`.

  For portraits:
  - Target is an NpcDefinition (by npc_id slug).
  - Builds prompt from appearance + personality (+ name/role).
  - Updates `portrait_url` on Authoring.NpcDefinition (Ash) and patches NpcInstance snapshots.
  - Authored `portrait_url` from packs takes precedence (only generate if blank).
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 3

  require Logger
  import Ecto.Query
  import Ash.Query

  alias TalesForge.Repo
  alias TalesForge.Schemas.Scene

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, job} <- normalize_args(args) do
      Logger.info("GenerateImage starting type=#{job.type} target=#{job.target_id}")

      case job.type do
        :scene -> generate_scene_image(job)
        :portrait -> generate_portrait_image(job)
      end
    end
  end

  # --- Args contract (string/atom keys → one shape) ---

  @doc false
  def normalize_args(args) when is_map(args) do
    type_raw = arg(args, :type)
    target_id = arg(args, :target_id)

    case parse_type(type_raw) do
      {:ok, type} when is_binary(target_id) and target_id != "" ->
        {:ok,
         %{
           type: type,
           target_id: target_id,
           session_id: arg(args, :session_id),
           narrative: arg(args, :narrative) || "",
           location_name: arg(args, :location_name) || target_id,
           npc_refs: arg(args, :npc_refs) || []
         }}

      {:ok, _type} ->
        Logger.error("GenerateImage: missing target_id args=#{inspect(args)}")
        {:error, :missing_target_id}

      {:error, _} = err ->
        err
    end
  end

  def normalize_args(_), do: {:error, :invalid_args}

  defp parse_type(type) when type in ["scene", :scene], do: {:ok, :scene}
  defp parse_type(type) when type in ["portrait", :portrait], do: {:ok, :portrait}

  defp parse_type(other) do
    Logger.error("GenerateImage: invalid type=#{inspect(other)}")
    {:error, :invalid_type}
  end

  defp arg(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp generate_scene_image(job) do
    %{
      target_id: location_id,
      session_id: session_id,
      narrative: narrative,
      location_name: location_name,
      npc_refs: npc_refs
    } = job

    prompt = build_scene_prompt(location_name, narrative, npc_refs)

    reference_images =
      npc_refs
      |> Enum.flat_map(fn ref ->
        purl = arg(ref, :portrait_url)
        if present?(purl), do: [purl], else: []
      end)
      # start with primary ref for API compatibility; text refs cover the rest
      |> Enum.take(1)

    image_url = generate_image_bytes(prompt, reference_images)

    # Future: download response bytes and upload to Tigris for a short permanent URL.
    # Currently returns direct image URL (xAI, pollinations, or mock).

    if is_binary(session_id) and session_id != "" do
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

  defp generate_portrait_image(%{target_id: npc_id}) do
    # Load via Ash (authoring) using filter on the stable npc_id (like importer does).
    # Ash.get with slug may not resolve (pk is uuid); filter does.
    case Ash.read(TalesForge.Authoring.NpcDefinition |> filter(npc_id == ^npc_id), load: []) do
      {:ok, [defn | _]} ->
        if is_nil(defn.portrait_url) or defn.portrait_url == "" do
          name = defn.name || npc_id
          desc = defn.appearance || defn.backstory || ""
          pers = defn.personality || ""
          role = defn.role || ""

          prompt = build_portrait_prompt(name, desc, pers, role)
          image_url = generate_image_bytes(prompt)

          # Update authored definition (Ash) — matches importer usage
          TalesForge.Authoring.NpcDefinition.update!(defn, %{portrait_url: image_url})

          # Patch any live NpcInstance snapshots so existing sessions pick up the portrait
          update_portrait_on_instances(npc_id, image_url)

          # Broadcast for live views (e.g. admin show page)
          Phoenix.PubSub.broadcast(
            TalesForge.PubSub,
            "npc_definitions:#{npc_id}",
            {:portrait_updated, image_url}
          )

          Logger.info("GenerateImage portrait done npc=#{npc_id} url=#{image_url}")
        else
          Logger.info("GenerateImage portrait skipped (authored url present) npc=#{npc_id}")
        end

      _ ->
        Logger.warning("GenerateImage portrait: NpcDefinition not found for #{npc_id}")
    end

    :ok
  end

  defp update_portrait_on_instances(npc_id, url) do
    alias TalesForge.Schemas.NpcInstance

    NpcInstance
    |> where([i], i.npc_id == ^npc_id)
    |> Repo.all()
    |> Enum.each(fn inst ->
      pers = inst.personality || %{}

      if Map.get(pers, "portrait_url") != url do
        new_pers = Map.put(pers, "portrait_url", url)

        inst
        |> NpcInstance.changeset(%{personality: new_pers})
        |> Repo.update()
      end
    end)
  end

  defp build_portrait_prompt(name, desc, pers, role) do
    # Use centralized style so portrait and scene images share identical
    # GM pencil-sketch instructions (DRY).
    base = gm_pencil_sketch_style("character")

    subject =
      if role && role != "", do: "#{name}, #{role}", else: "#{name}"

    details =
      cond do
        desc != "" and pers != "" -> "#{subject}. #{desc}. Personality: #{pers}."
        desc != "" -> "#{subject}. #{desc}."
        pers != "" -> "#{subject}. Personality: #{pers}."
        true -> subject
      end

    base <> " Portrait of " <> details
  end

  defp build_scene_prompt(location_name, narrative, npc_refs) do
    desc = if narrative != "", do: narrative, else: "atmospheric location"

    # Use centralized style (see gm_pencil_sketch_style/1) so scene + portrait
    # generation always use the exact same pencil-sketch GM instructions.
    styled = gm_pencil_sketch_style("scene")
    # Insert the scene-specific "expert GM sketch capturing..." sentence in the
    # same relative place it used to be (before the final "Tabletop..." constraints)
    # so the emitted prompt text stays familiar while the source instructions stay DRY.
    scene_desc = "Just an expert GM's sketch capturing the scene: #{desc} at #{location_name}. "

    base =
      String.replace(styled, "Tabletop RPG note style", scene_desc <> "Tabletop RPG note style",
        global: false
      )

    case npc_refs do
      [] ->
        base

      refs ->
        lines = Enum.map_join(refs, "\n", &npc_consistency_line/1)

        base <>
          "\n\nImportant character consistency (use known portraits for exact match): " <>
          "The following NPCs are present in the scene and their appearances must match " <>
          "their established portraits precisely:\n" <>
          lines
    end
  end

  defp npc_consistency_line(ref) do
    name = arg(ref, :name) || "NPC"
    app = arg(ref, :appearance) || ""
    pers = arg(ref, :personality) || ""
    purl = arg(ref, :portrait_url) || ""
    base_desc = if app != "", do: app, else: pers

    ref_part =
      if purl != "", do: " Reference and exactly match their portrait at #{purl}.", else: ""

    "- #{name}: #{base_desc}#{ref_part} Face, hair, clothing, build and overall appearance " <>
      "must be *identical* to their known portrait and description. " <>
      "Do not change or invent new features for this character."
  end

  # Centralized GM pencil-sketch style instructions.
  # Both build_portrait_prompt/4 and build_scene_prompt/3 call this so that
  # all images (scenes and NPC portraits) use *exactly* the same style wording.
  # This keeps the "very skilled GM drawing on paper" aesthetic DRY and consistent.
  defp gm_pencil_sketch_style(subject) do
    "Pencil sketch drawn by a very skilled game master (GM) on a plain sheet of paper using graphite pencil. " <>
      "Hand-drawn line art with fine natural pencil strokes, subtle paper texture and grain, light graphite shading. " <>
      "Strictly black and white, no color whatsoever, no paint, no oils, no digital rendering, no cinematic effects, " <>
      "no dramatic lighting, no polished illustration. " <>
      "Depict ONLY the visual #{subject} described by the following text. Do not include any text, letters, words, writing, signs, labels, or the description text itself anywhere in the image. " <>
      "Tabletop RPG note style, no text, no watermark, no borders, clean composition."
  end

  # Grok/xAI is the default (see Config.image_provider and XAI_API_KEY).
  # The prompt passed in is already built in the strong "GM pencil sketch on paper" style.
  # reference_images: list of portrait URLs (for character consistency in scenes).
  defp generate_image_bytes(prompt, reference_images \\ []) do
    refs = reference_images || []

    case TalesForge.Config.image_provider() do
      "xai" ->
        if present?(TalesForge.Config.xai_api_key()) do
          call_xai_image(prompt, refs)
        else
          pollinations_url(prompt)
        end

      "pollinations" ->
        pollinations_url(prompt)

      # "mock" and anything else: short deterministic URL, no network (tests / offline).
      _ ->
        mock_image_url(prompt)
    end
  end

  defp pollinations_url(prompt) do
    encoded = URI.encode(prompt)
    "https://image.pollinations.ai/prompt/#{encoded}?width=800&height=600&model=flux&safe=false"
  end

  defp mock_image_url(prompt) do
    seed = :erlang.phash2(prompt, 1_000_000)
    "https://placehold.co/800x600/png?text=sketch-#{seed}"
  end

  defp call_xai_image(prompt, reference_images) do
    # xAI Grok image generation (OpenAI-compatible /images/generations).
    # Only send prompt + n by default. For character consistency, include
    # reference image (portrait) if provided. Try URL first; on error the
    # caller falls back. Some backends prefer b64 data URL for "image".
    api_key = TalesForge.Config.xai_api_key()
    base = TalesForge.Config.xai_base() || "https://api.x.ai/v1"
    model = TalesForge.Config.xai_image_model()

    request_body =
      %{model: model, prompt: prompt, n: 1}
      |> maybe_put_reference_image(reference_images)

    case Req.post(
           "#{base}/images/generations",
           headers: [{"authorization", "Bearer " <> api_key}],
           json: request_body,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: %{"data" => [%{"url" => url} | _]}}} ->
        url

      {:ok, %{status: 200, body: %{"data" => [%{"b64_json" => b64} | _]}}} ->
        "data:image/png;base64,#{b64}"

      other ->
        Logger.warning("xAI image gen failed, falling back: #{inspect(other)}")
        pollinations_url(prompt)
    end
  end

  defp maybe_put_reference_image(body, []) do
    body
  end

  defp maybe_put_reference_image(body, [ref | _]) do
    image_ref =
      if String.starts_with?(ref, "http"), do: fetch_as_data_url(ref), else: ref

    Map.put(body, "image", image_ref)
  end

  # Fetch remote image (portrait) and return as data URL for reference use.
  defp fetch_as_data_url(url) do
    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: bytes, headers: headers}} ->
        content_type = content_type_from(headers, url)
        "data:#{content_type};base64,#{Base.encode64(bytes)}"

      _ ->
        # Fallback to url (some services may accept http urls directly)
        url
    end
  end

  defp content_type_from(headers, url) do
    from_header =
      Enum.find_value(headers, fn {k, v} ->
        if String.downcase(k) == "content-type", do: List.first(v)
      end)

    from_header || if(String.ends_with?(url, ".png"), do: "image/png", else: "image/jpeg")
  end

  defp present?(val), do: is_binary(val) and String.trim(val) != ""

  # Future: download image bytes + Tigris upload for short permanent URLs.

  defp update_scene_image(session_id, location_id, url) do
    Scene
    |> where([s], s.game_session_id == ^session_id and s.location_id == ^location_id)
    |> Repo.update_all(set: [image_url: url])
  end
end
