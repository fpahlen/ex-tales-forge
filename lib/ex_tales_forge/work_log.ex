defmodule TalesForge.WorkLog do
  @moduledoc """
  The founders' work log (board card "Work time auto log"; decision
  2026-10-12 "Work time auto log" in the docs repo).

  Each founder action writes one `TalesForge.WorkLog.Event` in the same
  transaction as the action. The v1 actions are in `kinds/0`. Bots and
  signed-out players write no event. Reading a card writes no event in v1.
  To count reading, add a kind and call `record/3` from the card open event.

  `TalesForge.WorkLog.Sessions` computes the work sessions from the stored
  events. No timer runs in memory, so a restart loses no time.

  Playtest is a separate app. Production copies the playtest events with
  `TalesForge.WorkLog.Peer`, the same pattern as `TalesForge.Online.Peer`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias TalesForge.AppRole
  alias TalesForge.Repo
  alias TalesForge.WorkLog.{Entry, Event, Sessions}

  @kinds ~w(comment move chat card_edit turn)

  @doc "The action types of v1."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "The label of an action type, for the work notes."
  @spec kind_label(String.t()) :: String.t()
  def kind_label("comment"), do: "card comment"
  def kind_label("move"), do: "card move"
  def kind_label("chat"), do: "team chat"
  def kind_label("card_edit"), do: "card edit"
  def kind_label("turn"), do: "game turn"
  def kind_label(other), do: other

  @doc "True for a founder email. False for a bot (`bot:<name>`) and for nil."
  @spec founder?(term()) :: boolean()
  def founder?("bot:" <> _), do: false
  def founder?(email) when is_binary(email), do: String.contains?(email, "@")
  def founder?(_), do: false

  @doc """
  Adds an event insert to `multi`. `step` names the earlier step that holds
  the source row. `founder_of` gets the founder from that row. The step
  writes nothing for a bot.
  """
  @spec add(Multi.t(), String.t(), atom(), (struct() -> String.t() | nil)) :: Multi.t()
  def add(%Multi{} = multi, kind, step, founder_of) when kind in @kinds do
    Multi.run(multi, :"work_log_#{step}", fn repo, changes ->
      row = Map.fetch!(changes, step)
      insert(repo, founder_of.(row), kind, row.id, row.inserted_at)
    end)
  end

  @doc """
  Writes one event now, outside a transaction. Returns `{:ok, event}`, or
  `{:ok, nil}` for a bot.
  """
  @spec record(String.t() | nil, String.t(), String.t()) ::
          {:ok, Event.t() | nil} | {:error, term()}
  def record(founder, kind, ref) when kind in @kinds,
    do: insert(Repo, founder, kind, ref, DateTime.utc_now())

  defp insert(repo, founder, kind, ref, at) do
    if founder?(founder) do
      %Event{}
      |> Event.changeset(%{
        founder: String.downcase(founder),
        kind: kind,
        app: app(),
        ref: to_string(ref),
        at: to_usec(at)
      })
      |> repo.insert()
    else
      {:ok, nil}
    end
  end

  @doc "The name of this app in the `app` field."
  @spec app() :: String.t()
  def app, do: Atom.to_string(AppRole.role())

  @doc "The events from `from` (inclusive) to `to` (exclusive), oldest first."
  @spec events(DateTime.t(), DateTime.t()) :: [Event.t()]
  def events(%DateTime{} = from, %DateTime{} = to) do
    Repo.all(from(e in Event, where: e.at >= ^from and e.at < ^to, order_by: [asc: e.at]))
  end

  @doc """
  The events of this app after `since`, oldest first, at most `limit`. The
  playtest peer endpoint serves these.
  """
  @spec local_events_after(DateTime.t(), pos_integer()) :: [Event.t()]
  def local_events_after(%DateTime{} = since, limit \\ 1_000) do
    app = app()

    Repo.all(
      from(e in Event,
        where: e.app == ^app and e.at > ^since,
        order_by: [asc: e.at],
        limit: ^limit
      )
    )
  end

  @doc "The time of the newest stored event of `app`, or nil."
  @spec latest_at(String.t()) :: DateTime.t() | nil
  def latest_at(app), do: Repo.one(from(e in Event, where: e.app == ^app, select: max(e.at)))

  @doc """
  Stores events from the other app (maps with string keys, as JSON gives
  them). Rows that exist already stay as they are. Returns the count of new rows.
  """
  @spec put_peer_events([map()], String.t()) :: non_neg_integer()
  def put_peer_events(list, app) when is_list(list) do
    now = DateTime.utc_now()

    rows =
      for %{"founder" => f, "kind" => k, "ref" => r, "at" => at} <- list,
          founder?(f) and k in @kinds and is_binary(r),
          {:ok, at, _} <- [DateTime.from_iso8601(to_string(at))] do
        %{
          id: Ecto.UUID.generate(),
          founder: String.downcase(f),
          kind: k,
          app: app,
          ref: r,
          at: to_usec(at),
          inserted_at: now
        }
      end

    {n, _} =
      Repo.insert_all(Event, rows, on_conflict: :nothing, conflict_target: [:app, :kind, :ref])

    n
  end

  @doc "The JSON form of an event for the peer endpoint."
  @spec to_json(Event.t()) :: map()
  def to_json(%Event{} = e),
    do: %{founder: e.founder, kind: e.kind, ref: e.ref, at: DateTime.to_iso8601(e.at)}

  @doc "The work sessions from `from` to `to` (`TalesForge.WorkLog.Sessions`)."
  @spec sessions(DateTime.t(), DateTime.t()) :: [Sessions.session()]
  def sessions(from, to), do: from |> events(to) |> Sessions.build()

  @doc """
  Adds a manual entry for `founder` (`TalesForge.WorkLog.Entry`). `attrs`
  has `date`, `hours` and `reason`. `added_by` is the signed-in founder.
  A founder can add an entry for another founder, for example for the
  spreadsheet import.
  """
  @spec add_entry(String.t(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def add_entry(added_by, attrs) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.reject(fn {_k, v} -> v in [nil, ""] end)

    %Entry{}
    |> Entry.changeset(
      Map.merge(%{"founder" => added_by}, attrs)
      |> Map.put("added_by", added_by)
    )
    |> Repo.insert()
  end

  @doc "The manual entries of the days `from` to `to` (both inclusive), oldest first."
  @spec entries(Date.t(), Date.t()) :: [Entry.t()]
  def entries(%Date{} = from, %Date{} = to) do
    Repo.all(
      from(e in Entry,
        where: e.date >= ^from and e.date <= ^to,
        order_by: [asc: e.date, asc: e.inserted_at]
      )
    )
  end

  defp to_usec(%DateTime{microsecond: {us, _}} = at), do: %{at | microsecond: {us, 6}}
end
