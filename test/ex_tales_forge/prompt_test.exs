defmodule TalesForge.PromptTest do
  @moduledoc "The prompt pipeline (`TalesForge.Prompt`) and the narration profile."
  use ExUnit.Case, async: true

  alias TalesForge.Prompt
  alias TalesForge.Prompt.{Ctx, Profile}

  defmodule StaticA do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :static_a, slot: :static
    @impl true
    def render(_ctx), do: "A"
  end

  defmodule SessionB do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :session_b, slot: :session
    @impl true
    def render(_ctx), do: "B"
  end

  defmodule TurnC do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :turn_c, slot: :turn
    @impl true
    def render(%{data: data}), do: data[:c]
  end

  defmodule TurnTail do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :turn_tail, slot: :turn
    @impl true
    def glue, do: ""
    @impl true
    def render(_ctx), do: "+tail"
  end

  defmodule Never do
    @moduledoc false
    use TalesForge.Prompt.Section, id: :never, slot: :turn
    @impl true
    def applies?(_ctx), do: false
    @impl true
    def render(_ctx), do: "never"
  end

  test "to_messages keeps the cache order static < session < turn" do
    messages =
      %Ctx{data: %{c: "C"}}
      |> Prompt.new()
      |> Prompt.add(TurnC)
      |> Prompt.add(Never)
      |> Prompt.add(SessionB)
      |> Prompt.add(StaticA)
      |> Prompt.add(TurnTail)
      |> Prompt.to_messages()

    assert messages == [
             %{role: "system", content: "A"},
             %{role: "user", content: "B"},
             %{role: "user", content: "C+tail"}
           ]
  end

  test "a section that renders nil is left out, and the glue follows the section" do
    prompt = %Ctx{data: %{c: nil}} |> Prompt.new() |> Prompt.add_all([TurnC, TurnTail])
    assert Prompt.render_slot(prompt, :turn) == "+tail"
    assert Prompt.ids(prompt) == [:turn_c, :turn_tail]
  end

  test "the narration profiles list their sections" do
    gm = Profile.sections(%Ctx{call: :gm}) |> Enum.map(& &1.id())
    scene = Profile.sections(%Ctx{call: :scene}) |> Enum.map(& &1.id())

    assert Enum.take(gm, 5) == [:narrator, :rules, :task, :character_sheet, :opening]
    assert List.last(gm) == :gm_turn_action
    assert scene == gm -- [:gm_turn_action]
  end
end
