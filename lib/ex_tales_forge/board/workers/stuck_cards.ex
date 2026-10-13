defmodule TalesForge.Board.Workers.StuckCards do
  @moduledoc """
  Reminds about stuck cards (bot cost cut, decision 2026-10-13 "Bot work in
  Elixir"; it replaces the refiner's hourly stuck card check). Hourly
  (`Oban.Plugins.Cron`, config), production only (`TalesForge.AppRole`).

  A card is stuck when it is in Building for 1 hour or more and has no linked
  PR. The card gets one comment with a fixed text (`text/0`) as `bot:board`.
  The text names no bot, so it wakes no bot. Each card gets the reminder only
  once: a card that already has this comment gets no second one.

  `stuck?/2` is the pure decision over a plain `%Card{}`. `run/1` reads the
  cards and writes the comments.
  """
  use Oban.Worker, queue: :board, max_attempts: 3, unique: [period: 300]

  import Ecto.Query

  alias TalesForge.AppRole
  alias TalesForge.Board
  alias TalesForge.Board.{Comment, Idea, Transition}
  alias TalesForge.Repo

  @author "bot:board"
  @after_s 3600
  @text "Reminder: this card is in Building for 1 hour or more and has no linked PR. " <>
          "Open the PR and link it to this card."

  defmodule Card do
    @moduledoc "The facts `stuck?/2` needs about a card."
    @enforce_keys [:id, :column, :building_since, :pr?, :reminded?]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            id: Ecto.UUID.t(),
            column: String.t(),
            building_since: DateTime.t() | nil,
            pr?: boolean(),
            reminded?: boolean()
          }
  end

  @doc "The fixed reminder text."
  @spec text() :: String.t()
  def text, do: @text

  @doc """
  True when the card gets the reminder now.

      iex> alias TalesForge.Board.Workers.StuckCards
      iex> card = %StuckCards.Card{id: "1", column: "building", pr?: false, reminded?: false,
      ...>   building_since: ~U[2026-10-13 06:00:00Z]}
      iex> StuckCards.stuck?(card, ~U[2026-10-13 07:00:00Z])
      true
      iex> StuckCards.stuck?(%{card | reminded?: true}, ~U[2026-10-13 07:00:00Z])
      false
      iex> StuckCards.stuck?(card, ~U[2026-10-13 06:59:59Z])
      false
  """
  @spec stuck?(Card.t(), DateTime.t()) :: boolean()
  def stuck?(
        %Card{
          column: "building",
          pr?: false,
          reminded?: false,
          building_since: %DateTime{} = since
        },
        now
      ),
      do: DateTime.diff(now, since) >= @after_s

  def stuck?(%Card{}, _now), do: false

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if AppRole.role() == :production, do: run(DateTime.utc_now())
    :ok
  end

  @doc "Comments on each stuck card. Returns the ids of the cards it reminded."
  @spec run(DateTime.t()) :: {:ok, [Ecto.UUID.t()]}
  def run(now) do
    ids =
      for idea <- building_ideas(),
          stuck?(card(idea), now),
          {:ok, _} <- [Board.add_comment(idea, @author, @text)],
          do: idea.id

    {:ok, ids}
  end

  defp building_ideas do
    from(i in Idea, where: i.column == "building", select: i.id)
    |> Repo.all()
    |> Enum.map(&Board.get_idea!/1)
  end

  defp card(%Idea{} = idea) do
    %Card{
      id: idea.id,
      column: idea.column,
      building_since: building_since(idea.id),
      pr?: Board.pr_number_of(idea) != nil,
      reminded?: reminded?(idea.id)
    }
  end

  defp building_since(id) do
    from(t in Transition,
      where: t.idea_id == ^id and t.to == "building",
      select: max(t.inserted_at)
    )
    |> Repo.one()
  end

  defp reminded?(id) do
    Repo.exists?(
      from(c in Comment, where: c.idea_id == ^id and c.author == @author and c.body == @text)
    )
  end
end
