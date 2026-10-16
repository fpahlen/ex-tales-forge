defmodule TalesForgeWeb.ThoughtEntryTest do
  @moduledoc false
  # The player character's thought in the story stream (board card 845b6b15).
  use TalesForgeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TalesForgeWeb.PlayComponents

  defp html(entry),
    do: render_component(&PlayComponents.thought_entry/1, id: "t1", entry: entry)

  test "a note with the Thought label, no Game Master heading, no Show all for short text" do
    out = html(%{role: "thought", text: "She meant it."})
    assert out =~ ~s(role="note")
    assert out =~ ~s(aria-label="Thought")
    assert out =~ "Thought"
    refute out =~ "Game Master"
    refute out =~ "Show all"
    refute out =~ "thought-about"
    assert out =~ "border-[var(--paper-thought-rule)]"
    assert out =~ "text-[var(--paper-thought-ink)]"
  end

  test "the about chip for a known NPC" do
    out = html(%{role: "thought", text: "She meant it.", about_name: "Elin Harrow"})
    assert out =~ ~s(aria-label="Thought about Elin Harrow")
    assert out =~ "thought-about"
    assert out =~ "EH"
  end

  test "a long thought clamps to 3 lines with Show all" do
    out = html(%{role: "thought", text: String.duplicate("a quiet ache ", 20)})
    assert out =~ "line-clamp-3"
    assert out =~ "Show all"
    assert out =~ ~s(aria-expanded="false")
    assert out =~ ~s(aria-controls="t1-thought-text")
  end
end
