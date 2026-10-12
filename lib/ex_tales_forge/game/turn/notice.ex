defmodule TalesForge.Game.Turn.Notice do
  @moduledoc """
  The stage after the mechanics and the NPC reactions, before the prompt
  (`SKILL_DETAIL_LEVEL=on`): the skill sets how much the character notices
  (`TalesForge.Game.Notice`). Writes `notice` (`level` and `details`) and adds
  it to the outcome record, so the turn log shows it. With the flag off the
  stage passes the turn through.
  """

  alias TalesForge.Game.Notice
  alias TalesForge.Game.Turn

  @doc "Writes `notice`."
  @spec select(Turn.t()) :: Turn.t()
  def select(%Turn{} = turn) do
    if Turn.flag?(turn, :skill_detail_level), do: notice(turn), else: turn
  end

  defp notice(%Turn{outcome: %{board: board, mechanical: mechanical} = outcome} = turn) do
    world = board.world
    level = level(mechanical, world)
    present = List.wrap(world["present_npcs"])

    view =
      world
      |> Map.put("npc_profiles", profiles(turn, present, level))
      |> Map.put("front_facts", front_facts(board))

    notice = %{level: level, details: Notice.details(view, mechanical.skill, level)}
    board = put_record(board, notice)
    %{turn | notice: notice, outcome: %{outcome | board: board}}
  end

  defp level(%{roll: roll} = mechanical, _world) when is_integer(roll),
    do: Notice.level(mechanical)

  defp level(_mechanical, world), do: Notice.passive_level(world)

  # No profile lookup when the level gives no detail.
  defp profiles(_turn, [], _level), do: []

  defp profiles(turn, present, level) do
    if Notice.count(level) > 0, do: turn.adapters.profiles.(turn.session.id, present), else: []
  end

  defp front_facts(board) do
    board
    |> Map.get(:sim, %{})
    |> Map.get(:fronts, [])
    |> Enum.flat_map(fn front ->
      definition = Map.get(front, :definition) || %{}
      List.wrap(definition["notice_facts"])
    end)
  end

  defp put_record(%{outcome: %{} = record} = board, notice),
    do: %{
      board
      | outcome:
          Map.put(record, "notice", %{
            "level" => Atom.to_string(notice.level),
            "details" => notice.details
          })
    }

  defp put_record(board, _notice), do: board
end
