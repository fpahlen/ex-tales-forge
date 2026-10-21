defmodule TalesForge.Locations.Destination do
  @moduledoc """
  Where the player's words send a move, before the intent reading's guess.
  Pure.

  A character travels only to a place that the world has and that has a
  route from where it is (teleportation aside). The words win over the
  reading: "back to the inn" goes to the place named "the inn", not to the
  inn yard the reading guessed (playtest session 9747d773, 2026-10-21). Words
  that send the character "to the X" where X is no place, person or spot it
  knows of give no move, and the GM is told "There's no X you know of."
  """

  alias TalesForge.Game.Movement

  @phrase ~r/\b(?:to|towards?)\s+the\s+([\p{L}' -]+?)(?=\s+(?:by|near|on|in|at|with|and|beside|of)\b|[,.!?;]|$)/iu
  # A general word ("the inn") is no name of its own.
  @stop ~w(the and inn)
  @lead_in ~r/\b(?:to|toward|towards|into|for|up|down|over|across|through|back|onto|reach|enter|visit)\s+(?:(?:the|that|this|a|old|its|their|his|her)\s+)*$/u

  @typedoc "What the words say about the move."
  @type t :: {:place, String.t()} | {:spot, String.t()} | {:unknown, String.t()} | nil

  @doc """
  The place the words name (`{:place, id}`), a spot of the room they name
  (`{:spot, phrase}`), a phrase that names nothing known (`{:unknown,
  phrase}`), or nil when the words name no destination.

      iex> world = %{"locations" => %{"inn" => %{"name" => "Valley Inn", "aliases" => ["the inn"]}}}
      iex> TalesForge.Locations.Destination.of(world, %{}, "I walk back to the inn.")
      {:place, "inn"}
      iex> TalesForge.Locations.Destination.of(world, %{}, "I walk to the castle.")
      {:unknown, "castle"}
      iex> TalesForge.Locations.Destination.of(world, %{"spots" => ["open hearth"]}, "I walk to the hearth.")
      {:spot, "hearth"}
      iex> TalesForge.Locations.Destination.of(world, %{}, "I look around.")
      nil
  """
  @spec of(map(), map(), String.t()) :: t()
  def of(world, context, text) when is_binary(text) do
    case named_place(world, text, here_and_around(world, context["location_id"])) do
      nil -> phrase(world, context, text)
      id -> {:place, id}
    end
  end

  def of(_world, _context, _text), do: nil

  # The place `text` names after a lead-in word ("back to the inn"),
  # reachable or not, other than those in `skip`.
  defp named_place(world, text, skip) do
    lowered = String.downcase(text)

    matches =
      for {id, loc} <- Movement.places(world),
          id not in skip,
          term <- terms(id, loc),
          {pos, stop} <- led_in(lowered, term),
          do: {id, pos, stop}

    matches |> Enum.reject(&runs_on?(&1, matches)) |> first_id()
  end

  # "To the inn yard": a longer name that runs on wins over "the inn".
  defp runs_on?({_id, pos, stop}, matches),
    do: Enum.any?(matches, fn {_other, p, s} -> p > pos and p < stop and s > stop end)

  defp first_id([]), do: nil

  defp first_id(matches),
    do: matches |> Enum.min_by(fn {_id, pos, stop} -> {pos, -stop} end) |> elem(0)

  # The id as words, the name without "the", the aliases as written ("the
  # cut", so "to cut off the chill" is no place).
  defp terms(id, loc) do
    name = loc["name"] |> to_string() |> String.downcase() |> String.replace_prefix("the ", "")
    aliases = Enum.map(List.wrap(loc["aliases"]), &String.downcase/1)
    Enum.uniq([String.replace(id, "_", " "), name | aliases]) -- [""]
  end

  # Where `term` stands in `lowered` right after a lead-in word, as `{start, stop}`.
  defp led_in(lowered, term) do
    for [{pos, len}] <-
          Regex.scan(~r/(?<![\w])#{Regex.escape(term)}(?![\w])/u, lowered, return: :index),
        Regex.match?(@lead_in, binary_part(lowered, max(pos - 40, 0), min(pos, 40))),
        do: {pos, pos + len}
  end

  # Where the character is and the places around it ("out into the street"
  # names the village around the inn): no destination, the way out decides
  # (`TalesForge.Locations.Exits`).
  defp here_and_around(world, here) when is_binary(here),
    do: [here | here_and_around(world, Movement.parent(world, here))]

  defp here_and_around(_world, _here), do: []

  defp phrase(world, context, text) do
    with [_, phrase] <- Regex.run(@phrase, text),
         phrase = String.trim(phrase),
         [_ | _] = named <- words(phrase) do
      cond do
        overlap?(named, Enum.flat_map(List.wrap(context["spots"]), &words/1)) -> {:spot, phrase}
        overlap?(named, known_words(world, context)) -> nil
        true -> {:unknown, phrase}
      end
    else
      _none -> nil
    end
  end

  # The words of every place, the fixtures here and the people.
  defp known_words(world, context) do
    (place_terms(world) ++ List.wrap(context["fixtures"]) ++ people_terms(context))
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(&words/1)
  end

  defp place_terms(world) do
    Enum.flat_map(Movement.places(world), fn {id, loc} ->
      [id, loc["name"] | List.wrap(loc["aliases"]) ++ List.wrap(loc["fixtures"])]
    end)
  end

  defp people_terms(context) do
    for key <- ["npc_details", "npc_locations"],
        {id, detail} <- Map.get(context, key) || %{},
        term <- [id, detail["name"], detail["role"]],
        do: term
  end

  defp words(text) do
    text
    |> to_string()
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3 and &1 not in @stop))
  end

  defp overlap?(words, other), do: Enum.any?(words, &(&1 in other))
end
