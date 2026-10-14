defmodule Workflow.Inbox.Store do
  @moduledoc """
  The edge of `Workflow.Inbox`: it stores the items in `inbox_items` and
  changes their state. The pure rules are in `Workflow.Inbox`.

  `add/3` runs in the `Ecto.Multi` of the change (`TalesForge.Board.Events`,
  `TalesForge.Chat`). Thus an item exists only when its source exists.
  Each new item also adds its web push job (`Workflow.Push.job/1`) in the
  same transaction.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Workflow.Inbox
  alias Workflow.Inbox.{Event, Item, Record}
  alias Workflow.Team

  @topic "workflow:inbox"

  @doc """
  Adds one step to `multi`. The step makes the event with `to_event` (from the
  changes so far), stores the items of `Workflow.Inbox.route/2` and closes the
  items of `Workflow.Inbox.closes/2`. `to_event` can give nil: then the step
  does nothing.
  """
  @spec add(Multi.t(), Team.t(), (map() -> Event.t() | nil)) :: Multi.t()
  def add(multi, %Team{} = team, to_event) when is_function(to_event, 1) do
    Multi.run(multi, {:inbox, System.unique_integer([:positive])}, fn repo, changes ->
      changes
      |> to_event.()
      |> apply_event(repo, team)
    end)
  end

  defp apply_event(nil, _repo, _team), do: {:ok, 0}

  defp apply_event(%Event{} = event, repo, team) do
    now = DateTime.utc_now()
    Enum.each(Inbox.closes(team, event), &close(repo, &1, now))
    {:ok, team |> Inbox.route(event) |> Enum.map(&insert(repo, &1, now)) |> length()}
  end

  defp insert(repo, %Item{} = item, now) do
    position =
      repo.one(from r in Record, where: r.recipient == ^item.recipient, select: max(r.position))

    %Record{}
    |> Map.merge(
      Map.take(item, ~w(recipient rule kind source source_id idea_id title author url)a)
    )
    |> Map.merge(%{body: item.body || "", position: (position || 0) + 1, created_at: now})
    |> repo.insert!(on_conflict: :nothing)
    |> tap(&push/1)
  end

  # The web push of the item goes into the same transaction (Workflow.Push).
  defp push(record) do
    case Workflow.Push.job(record) do
      nil -> :ok
      job -> {:ok, _job} = TalesForge.Workflow.Jobs.insert(job)
    end
  end

  defp close(repo, %{recipient: who, scope: scope}, now) do
    Record
    |> where([r], r.state == "new")
    |> where_scope(scope)
    |> then(&if(who == :all, do: &1, else: where(&1, [r], r.recipient == ^who)))
    |> repo.update_all(set: [state: "done", acted_at: now])
  end

  defp where_scope(q, :chat), do: where(q, [r], r.source == :chat)
  defp where_scope(q, {:idea, id}), do: where(q, [r], r.idea_id == ^id)

  defp where_scope(q, {:idea_rule, id, rule}),
    do: where(q, [r], r.idea_id == ^id and r.rule == ^rule)

  defp where_scope(q, {:source, source, source_id}),
    do: where(q, [r], r.source == ^source and r.source_id == ^source_id)

  defp where_scope(q, {:workflow, workflow}),
    do: where(q, [r], r.source == :github and r.title == ^workflow)

  @doc """
  Stores the items of one event that has no change of its own (a GitHub
  run), in one transaction, and tells the subscribers. Gives the number of
  new items.
  """
  @spec record(Team.t(), Event.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def record(%Team{} = team, %Event{} = event) do
    TalesForge.Workflow.Repo.transaction(fn repo ->
      {:ok, n} = apply_event(event, repo, team)
      n
    end)
    |> tap(fn _ -> broadcast() end)
  end

  @doc "The open items of `handle`, in queue order."
  @spec open(String.t() | nil) :: [Record.t()]
  def open(nil), do: []

  def open(handle) do
    from(r in Record,
      where: r.recipient == ^handle and r.state == "new",
      order_by: [asc: r.position, asc: r.created_at]
    )
    |> TalesForge.Workflow.Repo.all()
  end

  @doc "The number of open items of `handle`."
  @spec count(String.t() | nil) :: non_neg_integer()
  def count(nil), do: 0

  def count(handle),
    do:
      TalesForge.Workflow.Repo.aggregate(
        from(r in Record, where: r.recipient == ^handle and r.state == "new"),
        :count
      )

  @doc "One item by id, or nil."
  @spec get(String.t()) :: Record.t() | nil
  def get(id), do: TalesForge.Workflow.Repo.get(Record, id)

  @doc """
  Closes the open item `id` of `handle` with the state of `action`
  (`Workflow.Inbox.state_after/1`). An item that is closed already stays as
  it is.
  """
  @spec close_item(String.t(), String.t(), :approve | :answer | :done | :discard) ::
          :ok | {:error, :not_open}
  def close_item(id, handle, action) do
    from(r in Record, where: r.id == ^id and r.recipient == ^handle and r.state == "new")
    |> TalesForge.Workflow.Repo.update_all(
      set: [state: Inbox.state_after(action), acted_at: DateTime.utc_now()]
    )
    |> changed()
  end

  @doc "Puts the open item `id` of `handle` at the end of the queue."
  @spec skip(String.t(), String.t()) :: :ok | {:error, :not_open}
  def skip(id, handle) do
    position =
      from(r in Record, where: r.recipient == ^handle, select: r.position)
      |> TalesForge.Workflow.Repo.all()
      |> Inbox.skip_position()

    from(r in Record, where: r.id == ^id and r.recipient == ^handle and r.state == "new")
    |> TalesForge.Workflow.Repo.update_all(set: [position: position])
    |> changed()
  end

  defp changed({1, _}), do: tap(:ok, fn _ -> broadcast() end)
  defp changed({_, _}), do: {:error, :not_open}

  @doc "Subscribes the caller to inbox changes (`{:inbox, :changed}`)."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc "Tells the subscribers that an inbox changed. Call it after the commit."
  @spec broadcast() :: :ok
  def broadcast, do: Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:inbox, :changed})
end
