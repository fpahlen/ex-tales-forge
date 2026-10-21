defmodule TalesForge.Game.FirstMeeting do
  @moduledoc """
  Marks each present NPC as a first meeting or as one who has met the
  character (board card 84e11f16).

  Fredrik's rule: there is no new memory system. When the NPC's memory does
  not hold the character's name, the NPC does not know them. The step reads
  only the memory that the server has:

    * the NPC's memories (`runtime_state["memories"]`, written from the GM's
      `npc_memory_updates` and from fronts) that name the character (full or
      first name) or have a `"who"`. Secret memories and "Overheard ..."
      memories (written by the NPC on_overheard action) do not count: to hear
      someone in the room is not to meet them. With no character name, any
      other memory counts;
    * the NPC's dialogue lines (`world_state["npc_memory"]`,
      `TalesForge.Game.DialogueMemory`);
    * a relationship score that is not 0.

  Any of these means `:has_met`. Old sessions are not migrated: an NPC with
  no memory there is a first meeting.

  Pure: no Repo, no LLM.
  """

  @typedoc "The meeting status of one NPC."
  @type status :: :first_meeting | :has_met

  @doc """
  The status of an NPC from its runtime state, its dialogue lines and the
  character's name.

      iex> TalesForge.Game.FirstMeeting.status(%{"memories" => [], "relationship_score" => 0.0}, [], "Ezzor")
      :first_meeting
      iex> TalesForge.Game.FirstMeeting.status(%{"memories" => [%{"summary" => "Sold Ezzor rope."}]}, [], "Ezzor")
      :has_met
      iex> TalesForge.Game.FirstMeeting.status(%{"memories" => [%{"summary" => "Sold Tam rope."}]}, [], "Ezzor")
      :first_meeting
      iex> TalesForge.Game.FirstMeeting.status(%{"memories" => [%{"summary" => "Overheard player: Ezzor here."}]}, [], "Ezzor")
      :first_meeting
      iex> TalesForge.Game.FirstMeeting.status(%{"relationship_score" => 0.5}, [], "Ezzor")
      :has_met
      iex> TalesForge.Game.FirstMeeting.status(%{}, ["Two silver, no less."], "Ezzor")
      :has_met
      iex> TalesForge.Game.FirstMeeting.status(%{"memories" => [%{"summary" => "x", "secret" => true}]}, nil, nil)
      :first_meeting
  """
  @spec status(map() | nil, [String.t()] | nil, String.t() | nil) :: status()
  def status(runtime_state, dialogue_lines, character_name) do
    runtime = runtime_state || %{}

    if memories?(runtime["memories"], names(character_name)) or List.wrap(dialogue_lines) != [] or
         score?(runtime["relationship_score"]),
       do: :has_met,
       else: :first_meeting
  end

  defp memories?(memories, names),
    do: memories |> List.wrap() |> Enum.any?(&knows?(&1, names))

  defp knows?(%{"secret" => true}, _names), do: false

  defp knows?(%{} = memory, names) do
    text = to_string(memory["what"] || memory["summary"] || "")

    cond do
      String.starts_with?(text, "Overheard ") -> false
      Map.has_key?(memory, "who") -> true
      names == [] -> true
      true -> Enum.any?(names, &Regex.match?(~r/\b#{Regex.escape(&1)}\b/iu, text))
    end
  end

  defp knows?(_memory, _names), do: false

  defp names(name) when is_binary(name) and name != "" do
    name = String.trim(name)
    Enum.uniq([name, name |> String.split() |> hd()])
  end

  defp names(_name), do: []

  defp score?(score) when is_number(score), do: score != 0
  defp score?(_score), do: false

  @doc """
  The status of each NPC, by id. `npcs` are `{npc_id, runtime_state}` pairs;
  `dialogue_memory` is `world_state["npc_memory"]`.

      iex> TalesForge.Game.FirstMeeting.mark([{"drover", %{}}, {"innkeep", %{"relationship_score" => 1}}], %{}, "Ezzor")
      %{"drover" => :first_meeting, "innkeep" => :has_met}
  """
  @spec mark([{String.t(), map() | nil}], map() | nil, String.t() | nil) ::
          %{String.t() => status()}
  def mark(npcs, dialogue_memory, character_name) do
    Map.new(npcs, fn {id, runtime} ->
      {id, status(runtime, Map.get(dialogue_memory || %{}, id), character_name)}
    end)
  end

  @doc """
  The GM rule for the present NPCs, or nil when no NPC meets the character
  for the first time and no NPC has hooks. `npcs` are `{name, status,
  hooks?}`.

      iex> TalesForge.Game.FirstMeeting.rule([{"Brenna Holt", :has_met, false}])
      nil
      iex> TalesForge.Game.FirstMeeting.rule([{"Mags Ferrow", :first_meeting, true}]) =~ "Mags Ferrow"
      true
  """
  @spec rule([{String.t(), status(), boolean()}]) :: String.t() | nil
  def rule(npcs) do
    first = for {name, :first_meeting, _} <- npcs, do: name
    hooks? = Enum.any?(npcs, fn {_, _, h} -> h end)

    lines =
      if(first != [],
        do: [
          "First meeting: #{Enum.join(first, ", ")} has never met the character. " <>
            "They do not know the character and have never talked with them. " <>
            ~s(No "back again", no "as I said", no "still thinking on" and no earlier offer. ) <>
            "They may know the character by rumour or reputation, but they do not speak as if they talked before."
        ],
        else: []
      ) ++
        if(hooks?,
          do: [
            "Hooks are things an NPC can offer or say now. They are not things the NPC said to the character before."
          ],
          else: []
        )

    if lines != [], do: Enum.join(["## Meeting the character" | lines], "\n")
  end
end
