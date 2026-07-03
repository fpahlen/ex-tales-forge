defmodule TalesForge.Game.TurnProcessor do
  @moduledoc """
  Tier 2 GM response, server mechanics, and session persistence.
  """

  require Logger

  alias TalesForge.Game.ActionHandler
  alias TalesForge.Game.Context
  alias TalesForge.Game.Mechanics
  alias TalesForge.Game.Schemas.MechanicalResolution
  alias TalesForge.Game.World
  alias TalesForge.LLM
  alias TalesForge.PubSub.GameSession, as: SessionPubSub
  alias TalesForge.Repo
  alias TalesForge.Schemas.{GameSession, Turn}

  def run(session_id, raw_action, player_action_map) do
    started = System.monotonic_time(:millisecond)
    player_action = TalesForge.Game.Schemas.PlayerAction.decode(player_action_map)

    with %GameSession{} = session <- Repo.get(GameSession, session_id),
         turn_number <- next_turn_number(session_id),
         handler <- ActionHandler.resolve(player_action),
         gm_context <- Context.build_gm_context(session),
         {:ok, gm_result} <-
           LLM.complete_turn(
             TalesForge.Game.Prompts.gm_system(),
             Context.format_gm_prompt(gm_context),
             player_action,
             handler,
             turn_number
           ),
         {character, mechanical} <-
           apply_mechanics(
             session.world_state,
             gm_result.mechanical_resolution.skill,
             player_action,
             handler
           ),
         world_state <- apply_world_updates(session.world_state, character, handler, gm_result),
         {:ok, session} <- persist(session, world_state),
         {:ok, turn} <- persist_turn(session, turn_number, raw_action, gm_result, mechanical) do
      entries = build_entries(raw_action, gm_result.narrative, mechanical, turn.id)

      payload = %{
        session_id: session_id,
        turn_count: turn_number,
        entries: entries,
        mechanical_resolution: MechanicalResolution.encode(mechanical),
        llm_provider: LLM.provider(),
        llm_source: LLM.llm_source(LLM.provider()),
        location_name: Map.get(world_state, "location_name"),
        world_state: world_state
      }

      elapsed = System.monotonic_time(:millisecond) - started

      Logger.info(
        "turn completed session=#{session_id} turn=#{turn_number} duration_ms=#{elapsed} llm_source=#{LLM.llm_source(LLM.provider())}"
      )

      SessionPubSub.broadcast(session_id, {:turn_completed, payload})
      {:ok, payload}
    else
      nil ->
        {:error, :not_found}

      {:error, reason} = err ->
        Logger.error("turn processor failed session=#{session_id} reason=#{inspect(reason)}")
        SessionPubSub.broadcast(session_id, {:turn_failed, inspect(reason)})
        err
    end
  end

  defp apply_mechanics(world_state, gm_skill, player_action, handler) do
    character = Map.get(world_state, "character", %{})

    case Mechanics.apply_server_mechanics(character, gm_skill, player_action, handler) do
      {updated, %MechanicalResolution{} = resolution} -> {updated, resolution}
      %MechanicalResolution{} = resolution -> {character, resolution}
    end
  end

  defp apply_world_updates(world_state, character, handler, gm_result) do
    world_state =
      world_state
      |> put_in(["character"], character)
      |> maybe_move(handler)
      |> maybe_apply_context_summary(gm_result.context_summary)

    location_id = get_in(world_state, ["character", "location_id"])
    location = World.location(location_id)

    world_state
    |> Map.put("location_id", location_id)
    |> Map.put(
      "location_name",
      Map.get(location || %{}, "name", Map.get(world_state, "location_name"))
    )
  end

  defp maybe_move(world_state, %{handler: "move", state_hints: %{"location_id" => location_id}})
       when is_binary(location_id) do
    put_in(world_state, ["character", "location_id"], location_id)
  end

  defp maybe_move(world_state, %{handler: "move", target: target}) when is_binary(target) do
    put_in(world_state, ["character", "location_id"], target)
  end

  defp maybe_move(world_state, _), do: world_state

  defp maybe_apply_context_summary(world_state, nil), do: world_state

  defp maybe_apply_context_summary(world_state, summary) do
    lines =
      summary
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Map.put(world_state, "situation_lines", lines)
  end

  defp persist(%GameSession{} = session, world_state) do
    session
    |> GameSession.changeset(%{world_state: world_state})
    |> Repo.update()
  end

  defp persist_turn(session, turn_number, raw_action, gm_result, mechanical) do
    attrs = %{
      game_session_id: session.id,
      turn_number: turn_number,
      player_action: raw_action,
      narrative: gm_result.narrative,
      mechanical_resolution: MechanicalResolution.encode(mechanical)
    }

    %Turn{}
    |> Turn.changeset(attrs)
    |> Repo.insert()
  end

  defp next_turn_number(session_id) do
    import Ecto.Query

    Turn
    |> where([t], t.game_session_id == ^session_id)
    |> select([t], max(t.turn_number))
    |> Repo.one()
    |> case do
      nil -> 1
      n -> n + 1
    end
  end

  defp build_entries(raw_action, narrative, mechanical, turn_id) do
    [
      %{id: "#{turn_id}-player", role: "player", text: raw_action},
      %{
        id: "#{turn_id}-gm",
        role: "gm",
        text: narrative,
        mechanical: MechanicalResolution.encode(mechanical)
      }
    ]
  end
end
