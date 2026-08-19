defmodule TalesForge.ImagesTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Images
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, Scene}
  alias TalesForge.Workers.GenerateImage

  describe "normalize_args/1" do
    test "accepts atom keys" do
      assert {:ok, job} =
               GenerateImage.normalize_args(%{
                 type: :scene,
                 target_id: "weary_pilgrim",
                 session_id: "sess-1",
                 narrative: "A smoky tavern."
               })

      assert job.type == :scene
      assert job.target_id == "weary_pilgrim"
      assert job.session_id == "sess-1"
      assert job.narrative == "A smoky tavern."
    end

    test "accepts string keys (Oban JSON shape)" do
      assert {:ok, job} =
               GenerateImage.normalize_args(%{
                 "type" => "portrait",
                 "target_id" => "marta_kellen"
               })

      assert job.type == :portrait
      assert job.target_id == "marta_kellen"
      assert job.npc_refs == []
    end

    test "rejects invalid type" do
      assert {:error, :invalid_type} =
               GenerateImage.normalize_args(%{type: "banner", target_id: "x"})
    end

    test "rejects missing target_id" do
      assert {:error, :missing_target_id} =
               GenerateImage.normalize_args(%{type: :scene})
    end
  end

  describe "enqueue" do
    test "enqueue_scene_image inserts an images-queue job" do
      assert {:ok, %Oban.Job{} = job} =
               Images.enqueue_scene_image("weary_pilgrim", %{
                 session_id: Ecto.UUID.generate(),
                 narrative: "Candlelight and wet cloaks.",
                 location_name: "The Weary Pilgrim"
               })

      assert job.queue == "images"
      assert job.args["type"] == "scene" or job.args[:type] in ["scene", :scene]
      assert job.args["target_id"] == "weary_pilgrim" or job.args[:target_id] == "weary_pilgrim"
    end

    test "enqueue_portrait inserts an images-queue job" do
      assert {:ok, %Oban.Job{} = job} = Images.enqueue_portrait("marta_kellen")
      assert job.queue == "images"
      assert job.args["type"] == "portrait" or job.args[:type] in ["portrait", :portrait]
    end
  end

  describe "perform scene" do
    test "updates scene image_url and broadcasts with mock provider" do
      session =
        %GameSession{}
        |> GameSession.changeset(%{
          name: "Image Scene Test",
          world_state: %{"location_id" => "weary_pilgrim"}
        })
        |> Repo.insert!()

      scene =
        %Scene{}
        |> Scene.changeset(%{
          game_session_id: session.id,
          location_id: "weary_pilgrim",
          location_name: "The Weary Pilgrim",
          narrative: "Rain drums on the shutters of a dim tavern."
        })
        |> Repo.insert!()

      assert is_nil(scene.image_url)

      topic = TalesForge.PubSub.GameSession.topic(session.id)
      Phoenix.PubSub.subscribe(TalesForge.PubSub, topic)

      assert :ok =
               GenerateImage.perform(%Oban.Job{
                 args: %{
                   "type" => "scene",
                   "target_id" => "weary_pilgrim",
                   "session_id" => session.id,
                   "narrative" => scene.narrative,
                   "location_name" => scene.location_name
                 }
               })

      refreshed = Repo.get!(Scene, scene.id)
      assert is_binary(refreshed.image_url)
      assert refreshed.image_url =~ "placehold.co"

      assert_receive {:scene_image_ready,
                      %{
                        session_id: sid,
                        location_id: "weary_pilgrim",
                        image_url: url
                      }},
                     1_000

      assert sid == session.id
      assert url == refreshed.image_url
    end

    test "perform returns error for invalid type" do
      assert {:error, :invalid_type} =
               GenerateImage.perform(%Oban.Job{
                 args: %{"type" => "logo", "target_id" => "x"}
               })
    end
  end

  describe "perform portrait" do
    test "skips when portrait_url already authored" do
      import Ash.Query

      npc_id = "test_portrait_skip_#{System.unique_integer([:positive])}"

      assert {:ok, _defn} =
               TalesForge.Authoring.NpcDefinition.create(%{
                 npc_id: npc_id,
                 name: "Skip Portrait NPC",
                 portrait_url: "https://example.com/authored.png"
               })

      assert :ok =
               GenerateImage.perform(%Oban.Job{
                 args: %{"type" => "portrait", "target_id" => npc_id}
               })

      assert {:ok, [refreshed | _]} =
               Ash.read(
                 TalesForge.Authoring.NpcDefinition
                 |> filter(npc_id == ^npc_id),
                 load: []
               )

      assert refreshed.portrait_url == "https://example.com/authored.png"
    end

    test "generates portrait when blank (mock provider)" do
      assert {:ok, defn} =
               TalesForge.Authoring.NpcDefinition.create(%{
                 npc_id: "test_portrait_gen_#{System.unique_integer([:positive])}",
                 name: "Gen Portrait NPC",
                 appearance: "Weathered face, grey cloak",
                 personality: "Wary but kind",
                 portrait_url: nil
               })

      assert :ok =
               GenerateImage.perform(%Oban.Job{
                 args: %{"type" => "portrait", "target_id" => defn.npc_id}
               })

      import Ash.Query

      assert {:ok, [updated | _]} =
               Ash.read(
                 TalesForge.Authoring.NpcDefinition
                 |> filter(npc_id == ^defn.npc_id),
                 load: []
               )

      assert is_binary(updated.portrait_url)
      assert updated.portrait_url =~ "placehold.co"
    end

    test "missing npc definition is soft success" do
      assert :ok =
               GenerateImage.perform(%Oban.Job{
                 args: %{"type" => "portrait", "target_id" => "npc_does_not_exist_xyz"}
               })
    end
  end
end
