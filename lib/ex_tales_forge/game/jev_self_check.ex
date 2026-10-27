defmodule TalesForge.Game.JevSelfCheck do
  @moduledoc """
  The Jev side of the self-check (`TalesForge.Game.SelfCheck`), behind
  JEV_SELF_CHECK (`TalesForge.Config.jev_self_check?/0`, default off): the
  question in the read, and the answer as a `"self_check"` parameter.
  """

  alias TalesForge.Game.SelfCheck

  @doc """
  `questions` with the self-check question right after the manner (after the
  action in catalogue v1) when `on?` (default: JEV_SELF_CHECK=on). Off,
  `questions` unchanged.
  """
  @spec ask(keyword(), boolean()) :: keyword()
  def ask(questions, on? \\ TalesForge.Config.jev_self_check?())

  def ask(questions, false), do: questions

  def ask(questions, true) do
    after_key = if Keyword.has_key?(questions, :manner), do: :manner, else: :action
    at = Enum.find_index(questions, fn {key, _q} -> key == after_key end) + 1
    List.insert_at(questions, at, {:self_check, SelfCheck.question()})
  end

  @doc "`params` with Jev's self-check answer as `\"self_check\"`; no answer adds nothing."
  @spec put_param(map(), [SelfCheck.ask()] | nil) :: map()
  def put_param(params, nil), do: params

  def put_param(params, asks),
    do: Map.put(params, "self_check", Enum.map(asks, &Atom.to_string/1))
end
