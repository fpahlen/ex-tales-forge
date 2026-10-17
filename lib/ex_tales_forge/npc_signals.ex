defmodule TalesForge.NPCSignals do
  @moduledoc """
  Emits Jido signals to present NPC agents after turn processing.
  """

  require Logger

  alias Jido.AgentServer
  alias Jido.Signal
  alias TalesForge.Game.ActionHandler
  alias TalesForge.NPCRegistry
  alias TalesForge.NPCSignals.{Delivery, Turn}

  @doc "Sends the turn's signals to the present NPC agents: time passed, talked to, overheard."
  @spec emit_turn_signals(Turn.t()) :: :ok
  def emit_turn_signals(%Turn{handler: handler} = turn) do
    emit_time_passed(turn, tick_delta(turn))

    if speak_to_npc?(handler) do
      emit_player_talked(turn)
    end

    unless quiet?(handler) do
      emit_overhear(turn)
    end

    :ok
  end

  defp tick_delta(%Turn{world_before: %{"world_tick" => before}} = turn) when is_integer(before),
    do: world_tick(turn) - before

  defp tick_delta(%Turn{handler: handler}), do: ActionHandler.tick_delta(handler)

  defp world_tick(%Turn{world_state: world_state}), do: Map.get(world_state, "world_tick", 0)
  defp present_npcs(%Turn{world_state: world_state}), do: Map.get(world_state, "present_npcs", [])

  defp emit_time_passed(%Turn{session_id: session_id} = turn, delta_ticks) do
    payload = %{
      "session_id" => session_id,
      "world_tick" => world_tick(turn),
      "delta_ticks" => delta_ticks
    }

    Enum.each(present_npcs(turn), fn npc_id ->
      deliver(delivery(session_id, npc_id, "world.time.passed"), payload)
    end)
  end

  defp emit_player_talked(%Turn{session_id: session_id, handler: %{target: npc_id}} = turn) do
    payload = %{
      "session_id" => session_id,
      "npc_id" => npc_id,
      "player_text" => turn.raw_action,
      "world_tick" => world_tick(turn)
    }

    deliver(delivery(session_id, npc_id, "player.talked_to"), payload)
  end

  defp delivery(session_id, npc_id, type),
    do: %Delivery{session_id: session_id, npc_id: npc_id, type: type}

  defp deliver(%Delivery{} = delivery, payload) do
    aid = NPCRegistry.agent_id(delivery.session_id, delivery.npc_id)
    signal = Signal.new!(delivery.type, payload, source: "/game/turn_processor")

    case TalesForge.Jido.whereis(aid) do
      nil ->
        :ok

      pid ->
        call_agent(pid, signal, delivery)
    end
  end

  @doc false
  def call_agent(pid, signal, %Delivery{} = delivery) do
    case AgentServer.call(pid, signal) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        log_undelivered(delivery, reason)
    end
  catch
    :exit, {:noproc, _} = reason ->
      log_undelivered(delivery, reason)

    :exit, :noproc = reason ->
      log_undelivered(delivery, reason)
  end

  defp log_undelivered(%Delivery{} = d, reason) do
    Logger.debug(
      "npc signal undelivered session=#{d.session_id} npc=#{d.npc_id} type=#{d.type} reason=#{inspect(reason)}"
    )
  end

  defp emit_overhear(%Turn{session_id: session_id, handler: handler} = turn) do
    trimmed = String.trim(turn.raw_action || "")

    if trimmed != "" do
      speak_target = if speak_to_npc?(handler), do: handler.target, else: nil
      world_tick = world_tick(turn)

      turn
      |> present_npcs()
      |> Enum.reject(&(&1 == speak_target))
      |> Enum.each(fn npc_id ->
        deliver(delivery(session_id, npc_id, "conversation.message"), %{
          "session_id" => session_id,
          "speaker" => "player",
          "message" => trimmed,
          "world_tick" => world_tick
        })
      end)
    end
  end

  defp speak_to_npc?(%{handler: "speak", target: target}) when is_binary(target), do: true
  defp speak_to_npc?(_), do: false

  defp quiet?(%{handler: handler}) when handler in ["wait", "train"], do: true
  defp quiet?(_), do: false
end
