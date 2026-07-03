defmodule TalesForge.NPCRegistry do
  @moduledoc """
  Keeps Jido NPC agents aligned with `present_npcs` for a session.
  """

  require Logger

  alias TalesForge.Agents.NPCAgent
  alias TalesForge.NPC
  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  @agent_prefix "npc-"

  def agent_id(session_id, npc_id), do: "#{@agent_prefix}#{session_id}-#{npc_id}"

  def sync(%GameSession{} = session), do: sync(session.id, session.world_state || %{})

  def sync(session_id) when is_binary(session_id) do
    case Repo.get(GameSession, session_id) do
      %GameSession{} = session -> sync(session)
      nil -> {:error, :not_found}
    end
  end

  def sync(session_id, world_state) when is_binary(session_id) and is_map(world_state) do
    present = Map.get(world_state, "present_npcs", []) |> MapSet.new()
    desired = Enum.map(present, &agent_id(session_id, &1))

    running =
      session_id
      |> list_session_agent_ids()
      |> MapSet.new()

    desired_set = MapSet.new(desired)

    to_start = MapSet.difference(desired_set, running)
    to_stop = MapSet.difference(running, desired_set)

    Enum.each(to_start, &start_agent(session_id, agent_npc_id(session_id, &1)))
    Enum.each(to_stop, &stop_agent/1)
    Enum.each(to_stop, &await_agent_stopped/1)

    :ok
  end

  defp start_agent(session_id, npc_id) do
    aid = agent_id(session_id, npc_id)

    if TalesForge.Jido.whereis(aid) do
      :ok
    else
      initial_state = NPC.build_agent_state(session_id, npc_id)

      case TalesForge.Jido.start_agent(NPCAgent, id: aid, initial_state: initial_state) do
        {:ok, _pid} ->
          Logger.debug("npc agent started session=#{session_id} npc=#{npc_id}")
          :ok

        {:error, {:already_started, _pid}} ->
          :ok

        {:error, {:already_registered, _pid}} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "npc agent start failed session=#{session_id} npc=#{npc_id} reason=#{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp await_agent_stopped(agent_id) do
    Enum.reduce_while(1..20, :ok, fn _, _ ->
      if is_nil(TalesForge.Jido.whereis(agent_id)) do
        {:halt, :ok}
      else
        Process.sleep(5)
        {:cont, :ok}
      end
    end)
  end

  defp stop_agent(agent_id) do
    case TalesForge.Jido.whereis(agent_id) do
      nil ->
        :ok

      pid ->
        _ = TalesForge.Jido.stop_agent(pid)
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, _, _, _} ->
            Logger.debug("npc agent stopped id=#{agent_id}")
            :ok
        after
          1_000 ->
            Logger.warning("npc agent stop timed out id=#{agent_id}")
            :ok
        end
    end
  end

  defp list_session_agent_ids(session_id) do
    prefix = "#{@agent_prefix}#{session_id}-"

    TalesForge.Jido.list_agents()
    |> Enum.map(fn {id, _pid} -> id end)
    |> Enum.filter(&String.starts_with?(&1, prefix))
  end

  defp agent_npc_id(session_id, agent_id) do
    prefix = "#{@agent_prefix}#{session_id}-"
    String.replace_prefix(agent_id, prefix, "")
  end
end
