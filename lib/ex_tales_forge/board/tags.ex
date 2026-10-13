defmodule TalesForge.Board.Tags do
  @moduledoc """
  Tags on idea board cards. A card has two kinds of tag:

    * the founder tag: the author's display name in lower case (`"örjan"`),
      added automatically. A card that a bot wrote has no founder tag.
    * free-text tags that founders add and remove on the full card
      (`TalesForge.Board.Idea` field `tags`).

  Every tag is trimmed, in lower case, with single spaces, and at most
  24 characters long. The Ideas lane filters by tags with AND logic:
  a card shows when it has all the selected tags.

  The founder tag needs the team config (`Workflow.Team`), so the functions
  that read it get the team as their first argument.
  """

  alias TalesForge.Board.Idea

  @max 24

  @doc """
  The longest tag, in characters.

      iex> TalesForge.Board.Tags.max_length()
      24
  """
  @spec max_length() :: pos_integer()
  def max_length, do: @max

  @doc """
  Makes one tag from free text: trimmed, lower case, single spaces.
  Gives `{:error, message}` for an empty or a too long tag.

      iex> TalesForge.Board.Tags.normalize("  Combat   UI ")
      {:ok, "combat ui"}
      iex> TalesForge.Board.Tags.normalize(" ")
      {:error, "Type a tag."}
  """
  @spec normalize(term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize(text) when is_binary(text) do
    tag = text |> String.split() |> Enum.join(" ") |> String.downcase()

    cond do
      tag == "" -> {:error, "Type a tag."}
      String.length(tag) > @max -> {:error, "A tag has #{@max} characters or fewer."}
      true -> {:ok, tag}
    end
  end

  def normalize(_text), do: {:error, "Type a tag."}

  @doc """
  The selected tags from the `tags` URL query value (`"a,b"`): each one
  normalized, the invalid ones dropped, no duplicates.

      iex> TalesForge.Board.Tags.parse("UI, combat,,ui")
      ["ui", "combat"]
      iex> TalesForge.Board.Tags.parse(nil)
      []
  """
  @spec parse(term()) :: [String.t()]
  def parse(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.flat_map(fn t ->
      case normalize(t) do
        {:ok, tag} -> [tag]
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  def parse(_value), do: []

  @doc """
  The founder tag of an author email: the display name in lower case.
  A bot author (`bot:<name>`) gives nil.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Board.Tags.founder_tag(team, "bot:rita")
      nil
      iex> TalesForge.Board.Tags.founder_tag(team, "orjan.gh@example.com")
      "örjan"
  """
  @spec founder_tag(Workflow.Team.t(), String.t() | nil) :: String.t() | nil
  def founder_tag(_team, "bot:" <> _), do: nil

  def founder_tag(team, email) when is_binary(email),
    do: team |> TalesForge.TeamOnline.name(email) |> String.downcase()

  def founder_tag(_team, _email), do: nil

  @doc "All tags of a card: the founder tag first, then the free-text tags."
  @spec of(Workflow.Team.t(), Idea.t()) :: [String.t()]
  def of(team, %Idea{author: author, tags: tags}),
    do: Enum.uniq(List.wrap(founder_tag(team, author)) ++ (tags || []))

  @doc "The tags in use on the cards, sorted, each once."
  @spec in_use(Workflow.Team.t(), [Idea.t()]) :: [String.t()]
  def in_use(team, cards),
    do: cards |> Enum.flat_map(&of(team, &1)) |> Enum.uniq() |> Enum.sort()

  @doc """
  Keeps the cards that have all the selected tags (AND). No selected tag
  keeps every card.
  """
  @spec filter(Workflow.Team.t(), [Idea.t()], [String.t()]) :: [Idea.t()]
  def filter(_team, cards, []), do: cards

  def filter(team, cards, selected),
    do: Enum.filter(cards, fn card -> Enum.all?(selected, &(&1 in of(team, card))) end)

  @doc """
  The selected tags with `tag` added or, when it is there, removed.

      iex> TalesForge.Board.Tags.toggle(["ui"], "combat")
      ["ui", "combat"]
      iex> TalesForge.Board.Tags.toggle(["ui", "combat"], "ui")
      ["combat"]
  """
  @spec toggle([String.t()], String.t()) :: [String.t()]
  def toggle(selected, tag),
    do: if(tag in selected, do: List.delete(selected, tag), else: selected ++ [tag])
end
