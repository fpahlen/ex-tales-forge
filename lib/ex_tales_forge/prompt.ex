defmodule TalesForge.Prompt do
  @moduledoc """
  A prompt as a composable pipeline of sections.

      ctx
      |> Prompt.new()
      |> Prompt.add_all(Profile.static_sections(ctx))
      |> Prompt.add_all(Profile.session_sections(ctx))
      |> Prompt.add_all(Profile.turn_sections(ctx))
      |> Prompt.to_messages()

  Each section (`TalesForge.Prompt.Section`) has a slot: `:static`,
  `:session` or `:turn`. `to_messages/1` keeps the cache order
  static < session < turn, whatever the order of the `add` calls:

    * each `:static` section is one system message;
    * the `:session` sections are one user message;
    * the `:turn` sections are one user message, always last.

  A section that does not apply (`applies?/1`) or renders nil or `""` is left
  out. Sections in one user message are joined with `separator/0`, unless the
  section sets its own glue (`TalesForge.Prompt.Section.glue/1`).
  """

  alias TalesForge.Prompt.Ctx
  alias TalesForge.Prompt.Section

  defstruct ctx: nil, sections: []

  @type t :: %__MODULE__{ctx: Ctx.t(), sections: [module()]}
  @type message :: %{role: String.t(), content: String.t()}

  @separator "\n\n---\n\n"
  @slots [:static, :session, :turn]

  @doc "The separator between two sections of one user message."
  @spec separator() :: String.t()
  def separator, do: @separator

  @doc "An empty prompt for `ctx`."
  @spec new(Ctx.t()) :: t()
  def new(%Ctx{} = ctx), do: %__MODULE__{ctx: ctx}

  @doc "Adds one section."
  @spec add(t(), module()) :: t()
  def add(%__MODULE__{} = prompt, section) when is_atom(section) do
    unless section.slot() in @slots,
      do: raise(ArgumentError, "#{inspect(section)}: slot must be one of #{inspect(@slots)}")

    %{prompt | sections: prompt.sections ++ [section]}
  end

  @doc "Adds sections in order."
  @spec add_all(t(), [module()]) :: t()
  def add_all(%__MODULE__{} = prompt, sections), do: Enum.reduce(sections, prompt, &add(&2, &1))

  @doc "The ids of the sections that apply, in cache order."
  @spec ids(t()) :: [atom()]
  def ids(%__MODULE__{} = prompt) do
    prompt |> ordered() |> Enum.filter(& &1.applies?(prompt.ctx)) |> Enum.map(& &1.id())
  end

  @doc "The text of one slot (the sections that apply, joined), or `\"\"`."
  @spec render_slot(t(), Section.slot()) :: String.t()
  def render_slot(%__MODULE__{ctx: ctx} = prompt, slot) do
    prompt.sections
    |> Enum.filter(&(&1.slot() == slot))
    |> rendered(ctx)
    |> join()
  end

  @doc "The messages in cache order: system messages, then session, then turn."
  @spec to_messages(t()) :: [message()]
  def to_messages(%__MODULE__{ctx: ctx} = prompt) do
    static =
      prompt.sections
      |> Enum.filter(&(&1.slot() == :static))
      |> rendered(ctx)
      |> Enum.map(fn {_section, text} -> %{role: "system", content: text} end)

    users =
      for slot <- [:session, :turn],
          Enum.any?(prompt.sections, &(&1.slot() == slot)),
          do: %{role: "user", content: render_slot(prompt, slot)}

    static ++ users
  end

  defp ordered(%__MODULE__{sections: sections}) do
    Enum.sort_by(sections, &Enum.find_index(@slots, fn s -> s == &1.slot() end))
  end

  defp rendered(sections, ctx) do
    sections
    |> Enum.filter(& &1.applies?(ctx))
    |> Enum.map(&{&1, &1.render(ctx)})
    |> Enum.reject(fn {_section, text} -> is_nil(text) or text == "" end)
  end

  defp join([]), do: ""

  defp join([{_first, text} | rest]) do
    Enum.reduce(rest, text, fn {section, next}, acc ->
      acc <> Section.glue(section) <> next
    end)
  end
end
