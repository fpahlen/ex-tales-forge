defmodule TalesForge.Board.TransitionsTest do
  @moduledoc "The card state machine: every row of docs/design-board-states.md is a doctest."
  use ExUnit.Case, async: true

  alias TalesForge.Board.Transitions

  doctest Transitions

  @founder {:founder, "a@x"}
  @actors [@founder, {:bot, :case}, {:bot, :bobby}, {:bot, :gentry}, {:bot, :board}]
  @open %{up: 1, down: 0, refined: true, open_questions: 0, comment: "x", pr_linked: true}

  # The spec's move table: {from, to, actors}.
  @rows [
    {"ideas", "refining", [@founder]},
    {"ideas", "parked", [@founder]},
    {"refining", "check", [{:bot, :case}]},
    {"refining", "ideas", [@founder]},
    {"check", "building", [@founder]},
    {"check", "refining", [@founder]},
    {"check", "parked", [@founder]},
    {"building", "done", [{:bot, :bobby}, {:bot, :board}]},
    {"building", "refining", [{:bot, :bobby}, @founder]},
    {"parked", "ideas", [@founder]},
    {"ideas", "archived", [@founder]},
    {"parked", "archived", [@founder]},
    {"archived", "ideas", [@founder]}
  ]

  test "exactly the table's moves are possible, for exactly its actors" do
    for from <- Transitions.states(), to <- Transitions.states(), actor <- @actors do
      ok? =
        Enum.any?([:awaiting, :approved, nil], fn pr ->
          Transitions.allowed?(Map.put(@open, :pr, pr), from, to, actor) == :ok
        end)

      expected? = Enum.any?(@rows, fn {f, t, who} -> f == from and t == to and actor in who end)
      assert ok? == expected?, "#{from} → #{to} for #{inspect(actor)}"
    end
  end

  test "archive needs a reason; only a founder deletes, and only from Archived" do
    for from <- ~w(ideas parked) do
      assert {:error, "Write a short reason for the archive."} =
               Transitions.allowed?(%{comment: nil}, from, "archived", @founder)
    end

    for from <- Transitions.states(), actor <- @actors do
      expected = if from == "archived" and actor == @founder, do: :ok, else: :error
      assert elem_or_ok(Transitions.delete_allowed?(from, actor)) == expected
    end

    refute "archived" in Enum.map(Transitions.options(@open, "ideas", @founder), &elem(&1, 0))
  end

  defp elem_or_ok(:ok), do: :ok
  defp elem_or_ok({:error, _}), do: :error
end
