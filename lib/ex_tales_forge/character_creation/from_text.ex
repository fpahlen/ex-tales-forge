defmodule TalesForge.CharacterCreation.FromText do
  @moduledoc """
  The description model of character creation. The player writes a short
  description. One AI call reads it and returns labels, each with a
  confidence from 0 to 1: name, race, class, past occupation, stats and skills.

  * The AI can ask at most 2 questions. The player answers them, and a
    second call reads the description and the answers. The second call asks
    no questions.
  * `build/2` fills the draft through the normal functions:
    `CharacterCreation.choose_race/2`, `choose_class/2`, `choose_occupation/2`,
    `set_stat/3`, `set_skills/2` and `set_name/2`. A label with a confidence
    below `min_confidence/0` keeps the rules default. Elixir fits the stats
    to the point-buy budget and the range, so the draft is legal.
  * The player must approve the draft (`CharacterCreation.approve/1`). Then
    the draft ends with `validate/1` and `finalize/1`, as each model does.

  The AI call goes through an adapter (`FromText.Adapter`). The default adapter
  calls `TalesForge.LLM`, which writes one ai_calls row for each call.
  """

  alias TalesForge.CharacterCreation, as: CC
  alias TalesForge.CharacterCreation.Draft
  alias TalesForge.CharacterCreation.FromText.{Known, Label, Reading, StatLimits}

  @stats ~w(STR DEX CON INT WIS CHA)
  @max_questions 2
  @max_text 2000
  @min_confidence 0.5
  @fields ~w(name race class occupation)

  @typedoc "The labels and the questions from one reading."
  @type reading :: Reading.t()

  @doc "Returns the lowest confidence that `build/2` uses (0.5)."
  @spec min_confidence() :: float()
  def min_confidence, do: @min_confidence

  @doc "Returns the highest number of questions (2)."
  @spec max_questions() :: pos_integer()
  def max_questions, do: @max_questions

  @doc """
  Reads `description` for `adventure_id` with one AI call. `answers` holds the
  `{question, answer}` pairs from the first reading. With answers, the reading
  has no questions. Returns `{:ok, reading}` or `{:error, reason}`.
  """
  @spec read(String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, reading()} | {:error, term()}
  def read(adventure_id, description, answers \\ []) when is_binary(description) do
    text = description |> String.trim() |> String.slice(0, @max_text)

    if text == "" do
      {:error, :empty}
    else
      options = CC.options(adventure_id)

      case adapter().read(system_prompt(options), user_prompt(text, answers)) do
        {:ok, reply} when is_map(reply) ->
          {:ok, parse(reply, Known.from_options(options), answers)}

        {:ok, _other} ->
          {:error, :invalid_reply}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Fills `draft` from `reading` and sets the model to `"from_text"`. The draft
  is not approved. Labels with a confidence below `min_confidence/0` keep the
  rules default. Returns `{:ok, draft}`.
  """
  @spec build(Draft.t(), reading()) :: {:ok, Draft.t()}
  def build(%Draft{} = draft, %Reading{labels: labels}) do
    built = draft |> fresh_draft() |> apply_labels(labels)
    {:ok, %{built | text_labels: labels, approved: false}}
  end

  # --- reading ----------------------------------------------------------------------

  defp parse(reply, %Known{} = known, answers),
    do: %Reading{labels: labels(reply, known), questions: questions(reply, answers)}

  defp labels(reply, known) do
    @fields
    |> Map.new(&{&1, field_label(&1, reply[&1] || %{}, known)})
    |> Map.put("stats", stats_label(reply))
    |> Map.put("skills", skills_label(reply, known))
  end

  defp field_label(field, label, known) do
    value = label |> Map.get("value", "") |> to_string() |> String.trim() |> normalize(field)
    known? = field == "name" or value in Known.ids(known, field)
    confidence = if value != "" and known?, do: Label.confidence(label["confidence"]), else: 0.0
    %Label{value: value, confidence: confidence}
  end

  defp normalize(value, "name"), do: value
  defp normalize(value, _field), do: String.downcase(value)

  defp stats_label(reply) do
    value =
      for %{"stat" => s, "value" => v} <- List.wrap(reply["stats"]),
          s in @stats,
          is_integer(v),
          into: %{},
          do: {s, v}

    %Label{value: value, confidence: Label.confidence(reply["stats_confidence"])}
  end

  defp skills_label(reply, %Known{skills: skills}) do
    value =
      for %{"skill" => s, "level" => l} <- List.wrap(reply["skills"]),
          MapSet.member?(skills, s),
          is_integer(l) and l > 0,
          into: %{},
          do: {s, l}

    %Label{value: value, confidence: Label.confidence(reply["skills_confidence"])}
  end

  defp questions(reply, []) do
    reply["questions"]
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(@max_questions)
  end

  defp questions(_reply, _answers), do: []

  # --- building ---------------------------------------------------------------------

  defp apply_label(draft, %Label{value: value, confidence: c}, fun) when c >= @min_confidence do
    case fun.(draft, value) do
      {:ok, draft} -> draft
      {:error, _} -> draft
    end
  end

  defp apply_label(draft, _label, _fun), do: draft

  # A new draft for the same adventure and seed, keeping the dice roll.
  defp fresh_draft(%Draft{} = draft) do
    new = CC.new(draft.adventure_id, seed_key: draft.seed_key)

    {:ok, chosen} =
      %{new | rolled_stats: draft.rolled_stats, rerolls_left: draft.rerolls_left}
      |> CC.choose_model("from_text")

    chosen
  end

  defp apply_labels(draft, labels) do
    draft
    |> apply_label(labels["race"], &CC.choose_race/2)
    |> apply_label(labels["class"], &CC.choose_class/2)
    |> apply_label(labels["occupation"], &CC.choose_occupation/2)
    |> apply_stats(labels["stats"])
    |> apply_skills(labels["skills"])
    |> apply_label(labels["name"], &CC.set_name/2)
  end

  defp apply_stats(draft, %Label{value: wanted, confidence: c})
       when c >= @min_confidence and map_size(wanted) > 0 do
    CC.options(draft.adventure_id).point_buy
    |> StatLimits.new(CC.race_modifiers(draft))
    |> StatLimits.fit(wanted, draft.base_stats)
    |> Enum.reduce(draft, &set_stat/2)
  end

  defp apply_stats(draft, _label), do: draft

  defp set_stat({stat, value}, draft) do
    case CC.set_stat(draft, stat, value) do
      {:ok, draft} -> draft
      {:error, _} -> draft
    end
  end

  defp apply_skills(draft, %Label{value: wanted, confidence: c})
       when c >= @min_confidence and map_size(wanted) > 0 do
    free = CC.free_skills(draft)
    levels = Map.new(wanted, fn {s, l} -> {s, max(l, Map.get(free, s, 0))} end)

    with {:ok, set} <- CC.set_skills(draft, Map.merge(free, levels)),
         false <- skill_errors?(set) do
      set
    else
      _ -> CC.suggest_skills(draft)
    end
  end

  defp apply_skills(draft, _label), do: draft

  defp skill_errors?(draft) do
    case CC.validate(draft) do
      :ok -> false
      {:error, errors} -> Keyword.has_key?(errors, :skills)
    end
  end

  # --- prompts ----------------------------------------------------------------------

  defp system_prompt(options) do
    pb = options.point_buy

    """
    You read a player's description of a new role-playing character. Return JSON only.
    Give each label a value and a confidence from 0 to 1.
    Use only these values.
    Races: #{Enum.map_join(options.races, ", ", & &1.id)}.
    Classes: #{Enum.map_join(options.classes, ", ", & &1.id)}.
    Past occupations: #{Enum.map_join(options.occupations, ", ", & &1.id)}.
    Stats: #{Enum.join(@stats, ", ")}. Each stat is #{pb["min"]} to #{pb["max"]}. The stats total #{pb["budget"]} at most.
    Skills: #{Enum.map_join(options.skill_list, ", ", & &1.id)}. Levels 5 to 25 (1 to 100 scale, steps of 5).
    The name is the character's name from the text. Give an empty value when the text has no name.
    Give a high confidence only when the text states the value.
    Ask at most #{@max_questions} short questions, only for the labels with the lowest confidence.
    Ask questions only for labels with a low confidence.
    """
  end

  defp user_prompt(text, []), do: "Description:\n" <> text

  defp user_prompt(text, answers) do
    qa = Enum.map_join(answers, "\n", fn {q, a} -> "Q: #{q}\nA: #{a}" end)
    "Description:\n#{text}\n\nAnswers to your questions:\n#{qa}\n\nAsk no more questions."
  end

  defp adapter,
    do:
      Application.get_env(
        :ex_tales_forge,
        :character_text_adapter,
        TalesForge.CharacterCreation.FromText.LLMAdapter
      )
end
