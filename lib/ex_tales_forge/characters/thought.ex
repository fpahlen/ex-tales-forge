defmodule TalesForge.Characters.Thought do
  @moduledoc """
  The player character's thought (💭), PR 3 of board card 845b6b15. UI spec:
  Slick's thought-bubble design (`role: "thought"` stream entry).

  Triggers, at most one thought per turn:
    * `person`: an NPC present in the scene that the player character has
      a long- or short-term memory about. One per scene: a second person
      trigger in the same scene is dropped. With two NPCs, the heavier
      memory wins.
    * `sleep`: a long rest in the turn.
  A person trigger beats a sleep trigger.

  Jev gives typed labels, not prose, so the text comes from one small typed
  LLM call per trigger (`TalesForge.LLM.complete_thought/3`, ai_calls purpose
  `thought`). The text is feelings only: at most about 220 characters, and a
  reply with a digit is dropped.

  CHARACTER_MEMORY `on` shows the thought; `shadow` stores and logs it
  without showing it; `off` makes no call.

      iex> TalesForge.Characters.Thought.clean("I owe her 3 coins.")
      nil
      iex> TalesForge.Characters.Thought.clean("  She smiled like she meant it.  ")
      "She smiled like she meant it."
  """

  import Ecto.Query
  require Logger

  alias TalesForge.Characters
  alias TalesForge.Characters.{Memory, Moment}
  alias TalesForge.LLM
  alias TalesForge.Repo
  alias TalesForge.Schemas.{Character, CharacterMemory, SessionEvent, Turn}

  @max_chars 220
  @rows 5

  @system """
  You write one private thought of a player character in a fantasy story.
  First person, one or two short sentences, at most 220 characters.
  Feelings and impressions only. No numbers, prices, stats, dice, item names
  or quotation marks. Do not start with "I think". Use only names that appear
  in the memories. Reply as JSON: {"thought": "..."}.
  """

  @typedoc "A trigger: who or what the thought is about, with the memories."
  @type trigger ::
          {:person, Character.t(), [CharacterMemory.t()]}
          | {:sleep, [CharacterMemory.t()]}

  @doc """
  The thought of a turn as stored on `turns.thought`, or nil. Never raises.
  """
  @spec for_turn(Moment.t()) :: map() | nil
  def for_turn(%Moment{mode: :off}), do: nil

  def for_turn(%Moment{session_id: session_id} = moment) do
    with %Character{} = pc <- actor(moment),
         scene = scene_key(session_id, moment.world),
         trigger when not is_nil(trigger) <- trigger(moment, pc, scene),
         {:ok, text} <- text(pc, trigger, moment) do
      thought = build(trigger, text, scene)

      if moment.mode == :shadow,
        do: Logger.info("thought shadow session=#{session_id} #{inspect(thought)}")

      thought
    else
      _ -> nil
    end
  rescue
    e ->
      Logger.warning("thought failed session=#{session_id} #{Exception.message(e)}")
      nil
  end

  @doc "The stream entry of a stored thought; it goes right after the turn's GM entry."
  @spec entry(String.t(), map()) :: map()
  def entry(turn_id, thought) do
    %{
      id: "#{turn_id}-thought",
      role: "thought",
      text: thought["text"],
      about_name: thought["about_name"],
      about_portrait: thought["about_portrait"]
    }
  end

  @doc "True when thoughts show in the play stream (CHARACTER_MEMORY=on)."
  @spec visible?() :: boolean()
  def visible?, do: TalesForge.Config.character_memory() == :on

  # -- trigger -------------------------------------------------------------

  defp trigger(%Moment{} = moment, pc, scene) do
    person(moment, pc, scene) || sleep(pc, moment.events)
  end

  defp person(%Moment{session_id: session_id, world: world}, pc, scene) do
    present = List.wrap(world["present_npcs"])

    if present == [] or person_shown?(session_id, scene) do
      nil
    else
      case heaviest_memory(session_id, pc, present) do
        nil -> nil
        {npc, mems} -> {:person, npc, mems}
      end
    end
  end

  # The present NPC with the heaviest memory, and the memories.
  defp heaviest_memory(session_id, pc, present) do
    session_id
    |> Characters.list_for_session()
    |> Enum.filter(&(&1.slug in present))
    |> Enum.map(&{&1, Memory.recall(pc, [&1.slug], @rows)})
    |> Enum.reject(fn {_npc, mems} -> mems == [] end)
    |> Enum.max_by(fn {_npc, [top | _]} -> top.weight end, fn -> nil end)
  end

  defp sleep(pc, events) do
    if Memory.long_rest_in?(events) do
      case strongest(pc) do
        [] -> nil
        mems -> {:sleep, mems}
      end
    end
  end

  defp strongest(%Character{id: id}) do
    CharacterMemory
    |> where([m], m.character_id == ^id and m.tier in ["short", "long"])
    |> order_by([m], desc: m.weight, desc: m.tick)
    |> limit(@rows)
    |> Repo.all()
  end

  defp person_shown?(session_id, scene) do
    Turn
    |> where([t], t.game_session_id == ^session_id)
    |> where(
      [t],
      fragment("?->>'trigger' = 'person' AND ?->>'scene' = ?", t.thought, t.thought, ^scene)
    )
    |> Repo.exists?()
  end

  @doc false
  def scene_key(session_id, world) do
    travel =
      SessionEvent
      |> where([e], e.game_session_id == ^session_id and e.kind == "player.travel")
      |> select([e], max(e.tick))
      |> Repo.one()

    "#{world["location_id"]}:#{travel || 0}"
  end

  # The character whose Intention the turn played.
  defp actor(%Moment{actor: nil}), do: nil

  defp actor(%Moment{session_id: session_id, actor: slug}),
    do: Characters.get_by_slug(session_id, slug)

  # -- text ----------------------------------------------------------------

  defp text(pc, trigger, %Moment{session_id: session_id, turn_number: turn_number}) do
    user = prompt(pc, trigger)

    case LLM.complete_thought(@system, user, session_id: session_id, turn_number: turn_number) do
      {:ok, %{"thought" => raw}} ->
        case clean(raw) do
          nil -> {:error, :unusable}
          text -> {:ok, text}
        end

      other ->
        {:error, other}
    end
  end

  @doc false
  def prompt(pc, {:person, npc, mems}) do
    """
    Character: #{pc.name}. Mood: #{pc.mood || "calm"}.
    #{npc.name} is here now. Old memories about #{npc.name}:
    #{lines(mems)}
    Write the thought that comes up on seeing #{npc.name} again.
    """
  end

  def prompt(pc, {:sleep, mems}) do
    """
    Character: #{pc.name}. Mood: #{pc.mood || "calm"}.
    The character wakes after a long sleep. What stays from the day:
    #{lines(mems)}
    Write the thought on waking.
    """
  end

  defp lines(mems),
    do: Enum.map_join(mems, "\n", &"- #{&1.text}#{if &1.felt, do: " (felt #{&1.felt})"}")

  @doc "The text trimmed to #{@max_chars} characters, or nil when it has a digit or is empty."
  @spec clean(term()) :: String.t() | nil
  def clean(text) when is_binary(text) do
    text = text |> String.trim() |> String.trim("\"") |> String.trim()

    cond do
      text == "" -> nil
      String.match?(text, ~r/\d/) -> nil
      String.length(text) <= @max_chars -> text
      true -> shorten(text)
    end
  end

  def clean(_), do: nil

  defp shorten(text) do
    text
    |> String.slice(0, @max_chars - 1)
    |> String.replace(~r/\s+\S*$/u, "")
    |> Kernel.<>("…")
  end

  defp build({:person, npc, _mems}, text, scene),
    do: %{
      "text" => text,
      "trigger" => "person",
      "scene" => scene,
      "about_slug" => npc.slug,
      "about_name" => npc.name,
      "about_portrait" => (npc.definition || %{})["portrait_url"]
    }

  defp build({:sleep, _mems}, text, scene),
    do: %{"text" => text, "trigger" => "sleep", "scene" => scene}
end
