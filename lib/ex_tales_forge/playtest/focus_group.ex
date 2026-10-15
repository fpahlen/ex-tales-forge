defmodule TalesForge.Playtest.FocusGroup do
  @moduledoc """
  Persona focus group: the playtest personas talk about the game and say what
  they want us to improve. A founder runs it after a playtest batch with
  `mix focus_group.run`. It is off by default (`FOCUS_GROUP_ENABLED=true`
  turns it on).

  For each of the five personas (Hawk, Paul, Lotta, Lars, and Ronny as the red
  team) the run does these steps:

  1. Elixir builds the questions (`FocusGroup.Questions`) and a capped brief
     (`FocusGroup.Brief`).
  2. One LLM call with purpose `persona_interview` returns the typed reply
     `%{answers: [%{q_id, text}], top_improvements: [], quit_risks: []}`.
  3. Elixir checks the reply, groups the improvements by product gap and
     writes the Markdown report (`FocusGroup.Report`).

  The persona text comes from `TalesForge.Playtest.Personas` only. This module
  adds no personality model of its own.

  The answers are synthetic. Read them as structured brainstorming next to real
  playtest and forum evidence, not as customer research.
  """

  alias TalesForge.LLM
  alias TalesForge.Playtest.FocusGroup.{Brief, Questions}
  alias TalesForge.Playtest.Personas

  @persona_ids ~w(hawk paul lotta lars ronny)
  @red_team ~w(ronny)

  @typedoc "One persona's checked interview."
  @type interview :: %{
          persona: map(),
          red_team: boolean(),
          questions: [map()],
          answers: [%{q_id: String.t(), text: String.t()}],
          top_improvements: [String.t()],
          quit_risks: [String.t()],
          brief_tokens: non_neg_integer()
        }

  @doc "The persona ids in the focus group, in interview order."
  @spec persona_ids() :: [String.t()]
  def persona_ids, do: @persona_ids

  @doc "True for a red-team persona (Ronny)."
  @spec red_team?(String.t()) :: boolean()
  def red_team?(id), do: id in @red_team

  @doc """
  True when the focus group may run: `FOCUS_GROUP_ENABLED` is `"true"` or the
  app config `:focus_group_enabled` is `true`. The default is off.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:ex_tales_forge, :focus_group_enabled, false) == true or
      System.get_env("FOCUS_GROUP_ENABLED") == "true"
  end

  @doc """
  Interviews the personas. Returns `{:ok, interviews, failures}`, where
  `failures` is a list of `{persona_id, reason}`.

  Options:
  - `:personas` - persona ids (default: all five).
  - `:llm` - a 3-arity function with the shape of `LLM.complete_persona_interview/3`
    (tests).
  - `:session_summary` - a fixed summary for every brief (tests and dry runs).
  """
  @spec run(keyword()) :: {:ok, [interview()], [{String.t(), term()}]} | {:error, :disabled}
  def run(opts \\ []) do
    if enabled?() do
      ids = Keyword.get(opts, :personas, @persona_ids)
      llm = Keyword.get(opts, :llm, &LLM.complete_persona_interview/3)

      {oks, errors} =
        ids
        |> Enum.map(fn id -> {id, interview(id, llm, opts)} end)
        |> Enum.split_with(fn {_id, result} -> match?({:ok, _}, result) end)

      {:ok, Enum.map(oks, fn {_id, {:ok, i}} -> i end),
       Enum.map(errors, fn {id, {:error, reason}} -> {id, reason} end)}
    else
      {:error, :disabled}
    end
  end

  @doc "The system and user prompt for one persona, with no AI call."
  @spec prompts(map(), keyword()) :: %{system: String.t(), user: String.t(), brief: String.t()}
  def prompts(persona, opts \\ []) do
    brief = Brief.build(persona, opts)
    questions = Questions.for_persona(persona)
    %{system: system_prompt(persona), user: user_prompt(questions, brief), brief: brief}
  end

  defp interview(id, llm, opts) do
    with {:ok, persona} <- Personas.fetch(id),
         %{system: system, user: user, brief: brief} = prompts(persona, opts),
         {:ok, reply} <- llm.(system, user, []),
         {:ok, typed} <- decode(reply, Questions.ids(persona)) do
      {:ok,
       Map.merge(typed, %{
         persona: persona,
         red_team: red_team?(id),
         questions: Questions.for_persona(persona),
         brief_tokens: Brief.tokens(brief)
       })}
    end
  end

  defp system_prompt(persona) do
    role =
      if red_team?(persona.id),
        do:
          "You are on the red team. Speak as the exploiter: name the limits you could bend and what would stop you.",
        else: "Speak as a player who wants the game to be good for you."

    """
    You are #{persona.name}, a player of Tales Forge, a text role-playing game run by an AI Game Master. You are in a focus group after a playtest. Answer in the first person, in #{persona.name}'s own voice. #{role}

    #{persona.notes}

    How to answer:
    - Answer every question by its id. Use two or three short sentences for each answer.
    - Name concrete moments from your last session when you can.
    - top_improvements: at most three changes, most important first.
    - quit_risks: at most two things that would make you quit.
    """
  end

  defp user_prompt(questions, brief) do
    """
    #{brief}
    Questions:
    #{Enum.map_join(questions, "\n", &"- #{&1.id}: #{&1.text}")}
    """
  end

  @doc """
  Checks a reply against the typed shape (call type: function). Answers with an
  unknown `q_id` or empty text are dropped. The reply needs at least one answer.
  Lists are cut to three improvements and two quit risks.
  """
  @spec decode(map(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def decode(%{"answers" => answers} = reply, ids) when is_list(answers) do
    kept =
      for %{"q_id" => q, "text" => t} <- answers,
          q in ids,
          is_binary(t),
          String.trim(t) != "",
          do: %{q_id: q, text: String.trim(t)}

    case Enum.uniq_by(kept, & &1.q_id) do
      [] ->
        {:error, {:no_answers, reply}}

      kept ->
        {:ok,
         %{
           answers: Enum.sort_by(kept, &Enum.find_index(ids, fn id -> id == &1.q_id end)),
           top_improvements: strings(reply["top_improvements"], 3),
           quit_risks: strings(reply["quit_risks"], 2)
         }}
    end
  end

  def decode(reply, _ids), do: {:error, {:invalid_reply, reply}}

  defp strings(list, n) when is_list(list) do
    list
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.take(n)
  end

  defp strings(_other, _n), do: []

  @doc """
  Groups the improvements of all interviews by product gap (call type:
  function). An improvement goes to each gap with a keyword in its text, or to
  `"other"`. Returns `[{gap, [{persona_name, improvement}]}]`, the largest
  group first, with `"other"` last.
  """
  @spec themes([interview()]) :: [{map(), [{String.t(), String.t()}]}]
  def themes(interviews) do
    gaps = Brief.gaps()
    other = %{id: "other", title: "Other", keywords: [], text: ""}

    items =
      for i <- interviews, imp <- i.top_improvements do
        {i.persona.name, imp}
      end

    grouped =
      Enum.reduce(items, %{}, fn {_name, imp} = item, acc ->
        imp
        |> matching_gaps(gaps)
        |> case do
          [] -> [other]
          hits -> hits
        end
        |> Enum.reduce(acc, &Map.update(&2, &1, [item], fn list -> list ++ [item] end))
      end)

    grouped
    |> Enum.sort_by(fn {gap, list} -> {gap.id == "other", -length(list), gap.id} end)
  end

  defp matching_gaps(text, gaps) do
    words = text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    Enum.filter(gaps, fn gap -> Enum.any?(gap.keywords, &keyword_hit?(&1, words)) end)
  end

  defp keyword_hit?(keyword, words) do
    Enum.any?(words, &String.starts_with?(&1, String.downcase(keyword)))
  end
end
