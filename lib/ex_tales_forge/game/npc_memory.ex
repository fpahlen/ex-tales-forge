defmodule TalesForge.Game.NpcMemory do
  @moduledoc """
  NPC dialogue memory and the repetition guard (turn pipeline step 4, design
  §8; flag `NPC_DIALOGUE_MEMORY`).

  The server keeps the last 3 lines that each NPC spoke, in
  `world_state["npc_memory"]` (`%{npc_id => [line]}`, oldest first). The GM
  never writes the memory. After the GM call, the server finds the quoted
  lines in the prose, gives each line to the present NPC that the prose names
  next to it, and writes the memory.

  The GM prompt shows the memory of the present NPCs with the rule "do not
  repeat these lines" (design §5, rule 4). The repetition guard compares each
  new line with the memory. A line is a repeat when it is an exact match after
  the server lowers the case and collapses the whitespace
  (`TalesForge.Game.TurnRules.same_line?/2`, provisional). The guard logs each
  repeat and stores it as a `turn.npc_repeat` event. A repeat does not go into
  the memory a second time.

  Pure: no Repo, no LLM.
  """

  alias TalesForge.Game.TurnRules

  @max_lines 3
  @quote_re ~r/[“"]([^”"]{2,400})[”"]/u

  @typedoc "One NPC: id and the names that the prose can use."
  @type npc :: %{id: String.t(), names: [String.t()]}

  @doc "The maximum number of lines per NPC."
  @spec max_lines() :: pos_integer()
  def max_lines, do: @max_lines

  @doc """
  The quoted lines in `prose`, each with the NPC that speaks it. A line goes
  to the NPC that the prose names last before the quote, or else first after
  it in the same sentence. With one NPC present, an unnamed line goes to that
  NPC. A line with no speaker is dropped.

      iex> npcs = [%{id: "innkeep", names: ["Brenna Holt", "Brenna"]}, %{id: "rusk", names: ["Rusk"]}]
      iex> TalesForge.Game.NpcMemory.lines(~s(Brenna wipes a mug. "We close at midnight." Rusk laughs: "Not for me."), npcs)
      [{"innkeep", "We close at midnight."}, {"rusk", "Not for me."}]
  """
  @spec lines(String.t() | nil, [npc()]) :: [{String.t(), String.t()}]
  def lines(prose, npcs) when is_binary(prose) and npcs != [] do
    @quote_re
    |> Regex.scan(prose, return: :index)
    |> Enum.reduce({[], 0}, fn [{start, len}, {qs, ql}], {acc, from} ->
      before = binary_part(prose, from, start - from)
      after_text = prose |> binary_part(start + len, byte_size(prose) - start - len) |> sentence()
      line = binary_part(prose, qs, ql) |> String.trim()

      case speaker(before, after_text, npcs) do
        nil -> {acc, start + len}
        id -> {[{id, line} | acc], start + len}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  def lines(_prose, _npcs), do: []

  defp sentence(text), do: text |> String.split(~r/[.!?\n]/, parts: 2) |> hd()

  defp speaker(before, after_text, npcs) do
    last_named(before, npcs) || first_named(after_text, npcs) || only(npcs)
  end

  defp last_named(text, npcs) do
    npcs
    |> Enum.map(fn npc -> {npc.id, last_index(text, npc.names)} end)
    |> Enum.reject(fn {_id, i} -> is_nil(i) end)
    |> Enum.max_by(fn {_id, i} -> i end, fn -> {nil, nil} end)
    |> elem(0)
  end

  defp first_named(text, npcs) do
    npcs
    |> Enum.map(fn npc -> {npc.id, first_index(text, npc.names)} end)
    |> Enum.reject(fn {_id, i} -> is_nil(i) end)
    |> Enum.min_by(fn {_id, i} -> i end, fn -> {nil, nil} end)
    |> elem(0)
  end

  defp only([npc]), do: npc.id
  defp only(_npcs), do: nil

  defp last_index(text, names) do
    names
    |> Enum.flat_map(fn name ->
      ~r/\b#{Regex.escape(name)}\b/
      |> Regex.scan(text, return: :index)
      |> Enum.map(fn [{i, _}] -> i end)
    end)
    |> Enum.max(fn -> nil end)
  end

  defp first_index(text, names) do
    names
    |> Enum.flat_map(fn name ->
      case Regex.run(~r/\b#{Regex.escape(name)}\b/, text, return: :index) do
        [{i, _}] -> [i]
        _ -> []
      end
    end)
    |> Enum.min(fn -> nil end)
  end

  @doc """
  Writes the new lines into the memory. Returns the memory and the repeats
  (`{npc_id, line}`). A repeat is not written again. Each NPC keeps the last
  #{@max_lines} lines.

      iex> {memory, repeats} = TalesForge.Game.NpcMemory.put(%{"rusk" => ["Not for me."]}, [{"rusk", "not  for ME."}, {"rusk", "Go."}])
      iex> {memory, repeats}
      {%{"rusk" => ["Not for me.", "Go."]}, [{"rusk", "not  for ME."}]}
  """
  @spec put(map(), [{String.t(), String.t()}]) :: {map(), [{String.t(), String.t()}]}
  def put(memory, new_lines) do
    Enum.reduce(new_lines, {memory, []}, fn {id, line}, {mem, repeats} ->
      known = Map.get(mem, id, [])

      if Enum.any?(known, &TurnRules.same_line?(&1, line)) do
        {mem, repeats ++ [{id, line}]}
      else
        {Map.put(mem, id, Enum.take(known ++ [line], -@max_lines)), repeats}
      end
    end)
  end

  @doc """
  The NPCs present in `intent_context` with the names that can start a
  spoken line (the full name and the first name).
  """
  @spec present_npcs(map() | nil) :: [npc()]
  def present_npcs(intent_context) do
    details = (intent_context || %{})["npc_details"] || %{}

    (intent_context || %{})["present_npcs"]
    |> List.wrap()
    |> Enum.map(fn id ->
      name = get_in(details, [id, "name"]) || id
      %{id: id, names: Enum.uniq([name, name |> String.split() |> hd()])}
    end)
  end

  @doc "The session event for the repeats (kind `turn.npc_repeat`), or nil."
  @spec event([{String.t(), String.t()}], integer(), String.t() | nil) :: map() | nil
  def event([], _tick, _location_id), do: nil

  def event(repeats, tick, location_id) do
    %{
      "kind" => "turn.npc_repeat",
      "actor" => "server",
      "player_aware" => false,
      "tick" => tick,
      "location_id" => location_id,
      "payload" => %{
        "count" => length(repeats),
        "repeats" => Enum.map(repeats, fn {id, line} -> %{"npc_id" => id, "line" => line} end)
      }
    }
  end
end
