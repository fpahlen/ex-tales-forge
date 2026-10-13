defmodule TalesForge.Board.WakeMerge do
  @moduledoc """
  Merges duplicate bot wake-ups: at most one webhook wake for each bot and
  card in #{120} seconds (bot cost cut, decision 2026-10-13 "Bot work in
  Elixir"). A move and a mention on the same card within seconds give the bot
  one wake. The bot reads the card, so it sees the second event too.

  `wake?/3` is the pure decision. `TalesForge.Board.Events` reads the time of
  the last wake (`last_wake_at/2`) and asks `wake?/3` before it adds a
  `TalesForge.Board.Workers.Notify` job.
  """

  import Ecto.Query

  @window_s 120

  @doc """
  True when a new wake goes out: no earlier wake for this bot and card, or the
  last one is #{@window_s} seconds old or older.

      iex> now = ~U[2026-10-13 08:00:00Z]
      iex> TalesForge.Board.WakeMerge.wake?(nil, now)
      true
      iex> TalesForge.Board.WakeMerge.wake?(~U[2026-10-13 07:59:00Z], now)
      false
      iex> TalesForge.Board.WakeMerge.wake?(~U[2026-10-13 07:58:00Z], now)
      true
  """
  @spec wake?(DateTime.t() | nil, DateTime.t(), pos_integer()) :: boolean()
  def wake?(last_at, now, window_s \\ @window_s)
  def wake?(nil, _now, _window_s), do: true
  def wake?(%DateTime{} = last_at, now, window_s), do: DateTime.diff(now, last_at) >= window_s

  @doc "When the last `Notify` job for `bot` on card `idea_id` was added, or nil."
  @spec last_wake_at(Ecto.Repo.t(), atom(), String.t()) :: DateTime.t() | nil
  def last_wake_at(repo, bot, idea_id) do
    since = DateTime.add(DateTime.utc_now(), -@window_s)
    worker = inspect(TalesForge.Board.Workers.Notify)

    from(j in Oban.Job,
      where:
        j.worker == ^worker and j.inserted_at >= ^since and
          fragment("?->>'bot'", j.args) == ^Atom.to_string(bot) and
          fragment("?->'payload'->'idea'->>'id'", j.args) == ^idea_id,
      select: max(j.inserted_at)
    )
    |> repo.one()
    |> then(&(&1 && DateTime.from_naive!(&1, "Etc/UTC")))
  end
end
