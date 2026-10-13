defmodule TalesForge.Board do
  @moduledoc """
  The founders' idea board on `/team` (docs repo
  `docs/design-idea-board.md`, decisions 2026-10-10). Production only
  (`TalesForge.AppRole.here?(:board)`).

  Founders add ideas and vote them up or down (one vote each, +1 or -1,
  changeable; `vote/3`); the Ideas column is ranked by
  `TalesForge.Board.Ranking`. The refiner bot refines, founders check and
  comment, a founder moves the card to Building (the OK, which writes the
  decision log entry), the builder bot builds, the checker bot checks and the
  builder moves it to Done. The bot roles and names are in the team config
  (`Workflow.Team`). Who may move
  what is `TalesForge.Board.Transitions`; every move is a `board_transitions` row,
  and what it sets off (bot pings, the decision commit) is queued in the same
  transaction (`TalesForge.Board.Events`).

  Changes are broadcast on `topic/0` as `{:board, :changed}`.

  This module does IO (`TalesForge.Repo`), so it is an edge: it reads the
  team config from `Workflow.Team.Source` and gives it to the pure modules.
  """

  import Ecto.Query

  require Logger

  alias Ecto.Multi
  alias TalesForge.WorkLog
  alias Workflow.Team

  alias TalesForge.Board.{
    Answer,
    Approval,
    Comment,
    Deletion,
    Edit,
    Events,
    Idea,
    Link,
    Mentions,
    Ping,
    Ranking,
    Tags,
    Transition,
    Transitions,
    Vote
  }

  alias TalesForge.Collab.Schemas.Decision
  alias TalesForge.Workflow.Repo

  @topic "board:ideas"

  @typedoc "Who acts (see `TalesForge.Board.Transitions`)."
  @type actor :: Transitions.actor()

  @typedoc "An error for the UI or a bot: a sentence or a changeset."
  @type error :: {:error, String.t() | Ecto.Changeset.t()}

  @doc "The PubSub topic of board changes."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Subscribes the caller to board changes."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(TalesForge.PubSub, @topic)

  @doc """
  The whole board: a map of column => cards, with votes, comments, links and
  history loaded. Ideas are ranked (best first, with `:score` set fresh); the
  other columns are in the order the cards arrived there. Archived cards are
  not on the board (`archived/0`).
  """
  @spec board(DateTime.t()) :: %{String.t() => [Idea.t()]}
  def board(now \\ DateTime.utc_now()) do
    ideas = from(i in Idea, where: i.column in ^Idea.columns()) |> Repo.all() |> preload_all()
    grouped = Enum.group_by(ideas, & &1.column)

    Map.new(Idea.columns(), fn column ->
      cards = Map.get(grouped, column, [])
      {column, order(column, cards, now)}
    end)
  end

  @typedoc "Team totals of the board (`stats/0`): no names, only counts."
  @type stats :: %{
          columns: [%{id: String.t(), label: String.t(), count: non_neg_integer()}],
          totals: %{
            cards: non_neg_integer(),
            votes: non_neg_integer(),
            comments: non_neg_integer(),
            approvals: non_neg_integer(),
            founders: non_neg_integer()
          }
        }

  @doc """
  The board as team totals, for the founders' presentation: the card count
  of every column (in board order, with its label) and the team's totals of
  cards, votes, founder comments and PR approvals, plus how many founders
  took part (added, voted, commented or approved). Bot comments
  (`bot:` authors) do not count. It gives counts only, never a name.
  """
  @spec stats() :: stats()
  def stats do
    counts =
      from(i in Idea,
        where: i.column in ^Idea.columns(),
        group_by: i.column,
        select: {i.column, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    founder_comments = from(c in Comment, where: not like(c.author, "bot:%"))

    founders =
      [
        from(i in Idea, where: not like(i.author, "bot:%"), select: i.author),
        from(v in Vote, select: v.founder),
        select(founder_comments, [c], c.author),
        from(a in Approval, select: a.founder)
      ]
      |> Enum.flat_map(&Repo.all(distinct(&1, true)))
      |> MapSet.new()

    %{
      columns:
        Enum.map(Idea.columns(), fn column ->
          %{
            id: column,
            label: Transitions.label(team(), column),
            count: Map.get(counts, column, 0)
          }
        end),
      totals: %{
        cards: counts |> Map.values() |> Enum.sum(),
        votes: Repo.aggregate(Vote, :count),
        comments: Repo.aggregate(founder_comments, :count),
        approvals: Repo.aggregate(Approval, :count),
        founders: MapSet.size(founders)
      }
    }
  end

  @doc "The ranked Ideas column (best first), with fresh scores."
  @spec ranked_ideas(DateTime.t()) :: [Idea.t()]
  def ranked_ideas(now \\ DateTime.utc_now()) do
    from(i in Idea, where: i.column == "ideas")
    |> Repo.all()
    |> preload_all()
    |> then(&order("ideas", &1, now))
  end

  # The backlog: net votes, then total votes, both descending; then the
  # oldest card first.
  defp order("ideas", cards, now) do
    cards
    |> Enum.map(fn idea ->
      %{idea | score: Ranking.score(net_votes(idea), Ranking.age_days(idea.inserted_at, now))}
    end)
    |> Enum.sort_by(fn idea ->
      {-net_votes(idea), -length(idea.votes), DateTime.to_unix(idea.inserted_at, :microsecond)}
    end)
  end

  defp order(_column, cards, _now), do: Enum.sort_by(cards, &entered_at/1, {:asc, DateTime})

  defp entered_at(idea) do
    case Enum.max_by(idea.transitions, & &1.inserted_at, DateTime, fn -> nil end) do
      nil -> idea.inserted_at
      t -> t.inserted_at
    end
  end

  defp preload_all(query_or_ideas) do
    Repo.preload(query_or_ideas,
      votes: [],
      goal: [],
      comments: from(c in Comment, order_by: [asc: c.inserted_at, asc: c.id]),
      links: from(l in Link, order_by: [asc: l.inserted_at]),
      transitions: from(t in Transition, order_by: [asc: t.inserted_at, asc: t.id]),
      approvals: from(a in Approval, order_by: [asc: a.inserted_at, asc: a.id]),
      answers: [],
      images: from(i in TalesForge.Images.Image, order_by: [asc: i.inserted_at])
    )
  end

  @doc "The card's address on production's /team (its `#idea-<id>` anchor)."
  @spec url(Idea.t()) :: String.t()
  def url(%Idea{id: id}),
    do: String.trim_trailing(TalesForge.AppRole.base_url(:production), "/") <> "/team#idea-" <> id

  @doc "One card with everything loaded; raises when missing."
  @spec get_idea!(Ecto.UUID.t()) :: Idea.t()
  def get_idea!(id), do: Idea |> Repo.get!(id) |> preload_all()

  @doc "One card with everything loaded, or nil (also for a malformed id)."
  @spec get_idea(String.t()) :: Idea.t() | nil
  def get_idea(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Idea |> Repo.get(uuid) |> then(&(&1 && preload_all(&1)))
      :error -> nil
    end
  end

  @doc "The net votes of a card (votes loaded)."
  @spec net_votes(Idea.t()) :: integer()
  def net_votes(%Idea{votes: votes}) when is_list(votes),
    do: votes |> Enum.map(& &1.value) |> Enum.sum()

  @doc "True when any founder has a -1 vote on the card (votes loaded): it can't go to Building."
  @spec downvoted?(Idea.t()) :: boolean()
  def downvoted?(%Idea{votes: votes}), do: Enum.any?(votes, &(&1.value == -1))

  @doc "The vote of `founder` on the card (votes loaded): 1, -1 or nil."
  @spec vote_of(Idea.t(), String.t()) :: 1 | -1 | nil
  def vote_of(%Idea{votes: votes}, founder) do
    founder = normalize(founder)
    Enum.find_value(votes, &(&1.founder == founder && &1.value))
  end

  @doc """
  True when the checker bot has passed the card (a comment by the checker
  that starts with `check_pass/1`).

      iex> team = Workflow.Team.example()
      iex> pass = %TalesForge.Board.Comment{author: "bot:quill", body: "Quill check: pass. All good."}
      iex> TalesForge.Board.check_passed?(team, %TalesForge.Board.Idea{comments: [pass]})
      true
      iex> TalesForge.Board.check_passed?(team, %TalesForge.Board.Idea{comments: []})
      false
  """
  @spec check_passed?(Team.t(), Idea.t()) :: boolean()
  def check_passed?(%Team{} = team, %Idea{comments: comments}),
    do:
      Enum.any?(
        comments,
        &(&1.author == Team.actor(team, :checker) and
            String.starts_with?(&1.body, check_pass(team)))
      )

  @doc """
  The text a checker comment starts with when the check passed.

      iex> TalesForge.Board.check_pass(Workflow.Team.example())
      "Quill check: pass"
  """
  @spec check_pass(Team.t()) :: String.t()
  def check_pass(%Team{} = team), do: "#{Team.bot_name(team, :checker)} check: pass"

  @doc """
  Adds an idea to the Ideas column, by `founder` (an email, or `bot:<name>`
  for a card that a bot writes through the board API). Optional `tags`: a
  list of free-text tags (`TalesForge.Board.Tags`); a bad tag refuses the
  card. A new card always starts in Ideas and wakes no bot.
  """
  @spec create_idea(String.t(), map()) :: {:ok, Idea.t()} | error()
  def create_idea(founder, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, tags} <- new_tags(attrs["tags"], normalize(founder)) do
      insert_idea(founder, attrs, tags)
    end
  end

  defp new_tags(nil, _author), do: {:ok, []}

  defp new_tags(tags, author) when is_list(tags) do
    founder_tag = Tags.founder_tag(team(), author)

    Enum.reduce_while(tags, {:ok, []}, fn text, {:ok, acc} ->
      case Tags.normalize(text) do
        {:ok, tag} when tag == founder_tag -> {:cont, {:ok, acc}}
        {:ok, tag} -> {:cont, {:ok, if(tag in acc, do: acc, else: acc ++ [tag])}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp new_tags(_tags, _author), do: {:error, "Tags must be a list of words."}

  defp insert_idea(founder, attrs, tags) do
    Multi.new()
    |> Multi.insert(
      :idea,
      %Idea{}
      |> Idea.create_changeset(%{
        "title" => attrs["title"],
        "body" => attrs["body"] || "",
        "author" => normalize(founder)
      })
      |> Ecto.Changeset.put_change(:tags, tags)
    )
    |> Multi.insert(:transition, fn %{idea: idea} ->
      Transition.changeset(%Transition{}, %{
        idea_id: idea.id,
        to: "ideas",
        actor: normalize(founder)
      })
    end)
    |> run()
  end

  @doc """
  Sets `founder`'s vote on the card to `value` (1 or -1). A -1 needs a
  `reason`, saved with the vote. Voting the same value again takes the vote
  back (and its reason); the other value changes it. Only on cards in Ideas,
  Refining or Founder check. Votes do not move cards and wake nobody.
  """
  @spec vote(Idea.t(), String.t(), 1 | -1, String.t() | nil) :: {:ok, Idea.t()} | error()
  def vote(idea, founder, value, reason \\ nil)

  def vote(%Idea{} = idea, founder, value, reason) when value in [1, -1] do
    founder = normalize(founder)
    reason = if is_binary(reason), do: String.trim(reason), else: nil

    if idea.column in ~w(ideas refining check) do
      result =
        case Repo.get_by(Vote, idea_id: idea.id, founder: founder) do
          %Vote{value: ^value} = vote ->
            Repo.delete(vote)

          %Vote{} = vote ->
            vote |> Vote.changeset(%{value: value, reason: reason}) |> Repo.update()

          nil ->
            %Vote{}
            |> Vote.changeset(%{idea_id: idea.id, founder: founder, value: value, reason: reason})
            |> Repo.insert()
        end

      case result do
        {:ok, _} ->
          broadcast()
          {:ok, get_idea!(idea.id)}

        {:error, %Ecto.Changeset{errors: [{:reason, _} | _]}} ->
          {:error, "A downvote needs a reason. Write what needs work."}

        other ->
          other
      end
    else
      {:error, "Votes are closed once a card is in #{Transitions.label(team(), idea.column)}."}
    end
  end

  def vote(_idea, _founder, _value, _reason), do: {:error, "A vote is +1 or -1."}

  @doc """
  Adds a comment by `author` (a founder email or `bot:<name>`). `@<bot id>`
  wakes that bot. `@devops` wakes each bot of the team that has a webhook,
  once (see `TalesForge.Board.Mentions.wakes/3`). Only a
  comment by a founder wakes bots, as in the team chat: a comment by a bot
  wakes no bot, so a bot also never wakes itself (`comment_wakes/3`).
  `@<founder handle>` and
  `@founders` add an unread ping for each founder named, except the author
  (see `TalesForge.Board.Mentions`). On an archived card a comment wakes
  no bot and pings nobody. `opts[:login]` is the author's GitHub
  login, so the author gets no ping for their own name.
  """
  @spec add_comment(Idea.t(), String.t(), String.t(), keyword()) :: {:ok, Idea.t()} | error()
  def add_comment(%Idea{} = idea, author, body, opts \\ []) do
    author = normalize(author)
    changeset = Comment.changeset(%Comment{}, %{idea_id: idea.id, author: author, body: body})
    # A comment on an archived card stays on the card but wakes nobody.
    archived? = idea.column == "archived"
    team = team()
    %{founders: mentioned} = if archived?, do: %{founders: []}, else: Mentions.parse(team, body)
    founders = mentioned -- [Mentions.handle_for(team, opts[:login])]
    bots = if archived?, do: [], else: comment_wakes(team, author, body)

    Multi.new()
    |> Multi.insert(:comment, changeset)
    |> WorkLog.add("comment", :comment, & &1.author)
    |> Multi.run(:pings, fn repo, %{comment: comment} ->
      now = DateTime.utc_now()

      rows =
        for h <- founders,
            do: %{
              id: Ecto.UUID.generate(),
              idea_id: idea.id,
              comment_id: comment.id,
              handle: h,
              author: author,
              inserted_at: now
            }

      {n, _} = repo.insert_all(Ping, rows)
      {:ok, n}
    end)
    |> then(fn multi ->
      Enum.reduce(bots, multi, fn bot, acc ->
        Events.add(acc, :mention, idea, %{bot: bot, body: body, author: author})
      end)
    end)
    |> Events.add(:comment, idea, %{
      author_handle: Mentions.handle_for(team, opts[:login]),
      mentions: founders
    })
    |> run(idea.id)
    |> tap(fn _ -> Workflow.Inbox.Store.broadcast() end)
  end

  @doc """
  The bots a comment by `author` wakes. A founder's mention wakes the bot. A
  bot's comment wakes no bot, so a bot never wakes itself (the team chat rule,
  `TalesForge.Chat`).

      iex> TalesForge.Board.comment_wakes(Workflow.Team.example(), "bot:rita", "@rita and @bram, look")
      []
  """
  @spec comment_wakes(Team.t(), String.t(), String.t()) :: [atom()]
  def comment_wakes(%Team{} = team, author, body) do
    if TalesForge.Chat.founder?(author), do: Mentions.wakes(team, body), else: []
  end

  @doc """
  The bots mentioned in a comment.

      iex> TalesForge.Board.mentions(Workflow.Team.example(), "@Rita can you look? cc @quill, not @bramx")
      [:rita, :quill]
  """
  @spec mentions(Team.t(), String.t()) :: [atom()]
  def mentions(%Team{} = team, body), do: Mentions.parse(team, body, []).bots

  @doc """
  The unread pings of a founder (by GitHub login), one entry for each card, newest
  first: `%{idea_id, title, count, from, at}`. A founder with inbox rules
  (`Workflow.Inbox.has_inbox?/2`) gets no pings: the inbox replaces them.
  """
  @spec unread_pings(String.t()) :: [map()]
  def unread_pings(login) do
    team = team()

    case Mentions.handle_for(team, login) do
      nil ->
        []

      handle ->
        if Workflow.Inbox.has_inbox?(team, handle), do: [], else: pings_of(handle)
    end
  end

  defp pings_of(handle) do
    from(p in Ping,
      join: i in Idea,
      on: i.id == p.idea_id,
      where: p.handle == ^handle and is_nil(p.read_at) and i.column != "archived",
      order_by: [desc: p.inserted_at],
      select: {i.id, i.title, p.author, p.inserted_at}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {id, [{_, title, from, at} | _] = all} ->
      %{idea_id: id, title: title, count: length(all), from: from, at: at}
    end)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  @doc "Marks a founder's pings on a card as read (they opened the card)."
  @spec read_pings(String.t(), String.t()) :: non_neg_integer()
  def read_pings(idea_id, login) do
    with handle when is_binary(handle) <- Mentions.handle_for(team(), login),
         {n, _} when n > 0 <-
           from(p in Ping,
             where: p.idea_id == ^idea_id and p.handle == ^handle and is_nil(p.read_at)
           )
           |> Repo.update_all(set: [read_at: DateTime.utc_now()]) do
      broadcast()
      n
    else
      _ -> 0
    end
  end

  @doc """
  Adds a link (`kind`: pr, playtest, decision, doc, other). Only bots add
  links (`added_by` is `bot:<name>`, through the bot API): the builder the
  PR, the checker or the builder the playtest run. Links wake nobody.
  """
  @spec add_link(Idea.t(), String.t(), map()) :: {:ok, Idea.t()} | error()
  def add_link(%Idea{} = idea, "bot:" <> _ = added_by, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    changeset =
      Link.changeset(%Link{}, %{
        idea_id: idea.id,
        kind: attrs["kind"],
        url: attrs["url"],
        label: attrs["label"],
        added_by: added_by
      })

    Multi.new()
    |> Multi.insert(:link, changeset)
    |> run(idea.id)
    |> check_done_after(attrs["kind"] == "pr")
  end

  def add_link(%Idea{}, _added_by, _attrs) do
    team = team()
    builder = Team.bot_name(team, :builder)
    checker = Team.bot_name(team, :checker)
    {:error, "Bots add the links: #{builder} the PR, #{checker} or #{builder} the playtest run."}
  end

  @doc """
  Adds a free-text tag to a card (`TalesForge.Board.Tags`: trimmed, lower
  case, at most 24 characters). Only founders add tags. A tag that the card
  has already, or its founder tag, changes nothing.
  """
  @spec add_tag(Idea.t(), String.t(), String.t()) :: {:ok, Idea.t()} | error()
  def add_tag(%Idea{}, "bot:" <> _, _text), do: {:error, "Founders add the tags."}

  def add_tag(%Idea{} = idea, _founder, text) do
    with {:ok, tag} <- Tags.normalize(text) do
      if tag in Tags.of(team(), idea),
        do: {:ok, idea},
        else:
          idea
          |> Idea.update_changeset(%{tags: idea.tags ++ [tag]})
          |> Repo.update()
          |> after_update()
    end
  end

  @doc """
  Removes a free-text tag from a card. Only founders remove tags. The
  founder tag stays: it comes from the author.
  """
  @spec remove_tag(Idea.t(), String.t(), String.t()) :: {:ok, Idea.t()} | error()
  def remove_tag(%Idea{}, "bot:" <> _, _tag), do: {:error, "Founders remove the tags."}

  def remove_tag(%Idea{} = idea, _founder, tag) do
    if tag in idea.tags,
      do:
        idea
        |> Idea.update_changeset(%{tags: List.delete(idea.tags, tag)})
        |> Repo.update()
        |> after_update(),
      else: {:ok, idea}
  end

  @doc """
  Adds images to a card (`TalesForge.Images`): `images` is a list of image
  bytes, `uploader` a founder email, `note` an optional text for each image.
  Returns `{:ok, idea}`, or `{:error, message}` when a file is not a PNG, JPEG
  or WebP image or is too large. Then the card gets no image.
  """
  @spec add_images(Idea.t(), String.t(), [binary()], String.t() | nil) ::
          {:ok, Idea.t()} | error()
  def add_images(%Idea{}, _uploader, [], _note), do: {:error, "Add an image first."}

  def add_images(%Idea{} = idea, uploader, images, note) do
    case Enum.find_value(images, &image_error/1) do
      nil ->
        images
        |> Enum.with_index()
        |> Enum.reduce(Multi.new(), &store_image_step(&1, &2, idea.id, uploader, note))
        |> run(idea.id)

      message ->
        {:error, message}
    end
  end

  defp store_image_step({data, n}, multi, idea_id, uploader, note) do
    Multi.run(multi, {:image, n}, fn _repo, _changes ->
      TalesForge.Images.store({:idea, idea_id}, data, %{uploader: uploader, note: note})
    end)
  end

  defp image_error(data) do
    case TalesForge.Images.validate(data) do
      :ok -> nil
      {:error, message} -> message
    end
  end

  @refinement_keys ~w(details open_questions rough_cost verdict)
  @verdicts ~w(feasible feasible_with_caveats not_feasible)
  @costs ~w(S M L)

  @doc """
  The refiner's refinement of a card in Refining: `details` (text), `open_questions`
  (a list of strings), `rough_cost` (S, M or L) and `verdict` (feasible,
  feasible_with_caveats or not_feasible). Merged into what is there.

  `author` is the founder email or `"bot:<name>"` that makes the edit. The
  default is the refiner, the bot that refines cards. The
  same transaction writes one `TalesForge.Board.Edit` row with the author,
  the time and the changed fields.
  """
  @spec refine(Idea.t(), map(), String.t() | nil) :: {:ok, Idea.t()} | error()
  def refine(idea, attrs, author \\ nil)

  def refine(idea, attrs, nil), do: refine(idea, attrs, Team.actor(team(), :refiner))

  def refine(%Idea{column: "refining"} = idea, attrs, author) when is_binary(author) do
    attrs = attrs |> Map.new(fn {k, v} -> {to_string(k), v} end) |> Map.take(@refinement_keys)
    merged = Map.merge(idea.refinement || %{}, attrs)

    changed =
      attrs |> Map.keys() |> Enum.filter(&(Map.get(idea.refinement || %{}, &1) != attrs[&1]))

    with :ok <- valid_refinement(merged) do
      Multi.new()
      |> Multi.update(:idea, Idea.update_changeset(idea, %{refinement: merged}))
      |> Multi.insert(
        :edit,
        Edit.changeset(%Edit{}, %{
          idea_id: idea.id,
          author: normalize(author),
          fields: Enum.sort(changed)
        })
      )
      |> WorkLog.add("card_edit", :edit, & &1.author)
      |> Repo.transaction()
      |> case do
        {:ok, %{idea: idea}} -> after_update({:ok, idea})
        {:error, _step, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      end
    end
  end

  def refine(%Idea{}, _attrs, _author), do: {:error, "Only a card in Refining can be refined."}

  @doc "The card text edits from `since` on, oldest first."
  @spec edits_since(DateTime.t()) :: [Edit.t()]
  def edits_since(%DateTime{} = since),
    do: Repo.all(from(e in Edit, where: e.inserted_at >= ^since, order_by: e.inserted_at))

  defp valid_refinement(r) do
    cond do
      Map.has_key?(r, "open_questions") and not is_list(r["open_questions"]) ->
        {:error, "open_questions must be a list of strings."}

      Map.has_key?(r, "rough_cost") and r["rough_cost"] not in @costs ->
        {:error, "rough_cost must be S, M or L."}

      Map.has_key?(r, "verdict") and r["verdict"] not in @verdicts ->
        {:error, "verdict must be feasible, feasible_with_caveats or not_feasible."}

      true ->
        :ok
    end
  end

  @doc "True when the refinement has a verdict, a rough cost and its open questions (a list, may be empty)."
  @spec refined?(Idea.t()) :: boolean()
  def refined?(%Idea{refinement: r}) do
    is_list(r["open_questions"]) and r["rough_cost"] in @costs and r["verdict"] in @verdicts
  end

  @doc """
  The facts about a card that `TalesForge.Board.Transitions` needs (votes,
  links, approvals and refinement loaded), with the move's `comment`.
  """
  @spec facts(Idea.t(), String.t() | nil) :: Transitions.card()
  def facts(%Idea{} = idea, comment \\ nil) do
    %{
      up: Enum.count(idea.votes, &(&1.value == 1)),
      down: Enum.count(idea.votes, &(&1.value == -1)),
      refined: refined?(idea),
      open_questions: idea |> questions() |> Enum.count(fn {_q, a} -> not Answer.settled?(a) end),
      comment: comment,
      pr: pr_state(idea),
      pr_linked: idea.pr_number != nil or Enum.any?(idea.links, &(&1.kind == "pr"))
    }
  end

  @doc """
  The open questions of the refinement, each with its answer (or nil),
  in the refiner's order (answers loaded).
  """
  @spec questions(Idea.t()) :: [{String.t(), Answer.t() | nil}]
  def questions(%Idea{} = idea) do
    answers = Map.new(idea.answers, &{&1.question, &1})

    (idea.refinement || %{})["open_questions"]
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(&{&1, answers[&1]})
  end

  @doc """
  A founder answers one open question (`attrs`: `"answer"`), or defers it
  (`"deferred"`: true / false). Any founder may defer or undefer; an answer
  can be changed only by the founder who wrote it. Writes a line in the
  card's history; while the card is in Refining it wakes the refiner
  (`question.answered`, see `TalesForge.Board.Transitions.event_wakes/3`).
  """
  @spec answer_question(Idea.t(), String.t(), String.t(), map()) :: {:ok, Idea.t()} | error()
  def answer_question(%Idea{}, "bot:" <> _, _question, _attrs),
    do: {:error, "Founders answer the open questions."}

  def answer_question(%Idea{} = idea, founder, question, attrs) do
    idea = get_idea!(idea.id)
    founder = normalize(founder)
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    now = DateTime.utc_now()

    with {^question, current} <-
           Enum.find(questions(idea), {:error, nil}, fn {q, _} -> q == question end),
         {:ok, change, note} <- answer_change(current, founder, attrs, now, question) do
      row = current || %Answer{idea_id: idea.id, question: question}

      Multi.new()
      |> Multi.insert_or_update(:answer, Answer.changeset(row, change))
      |> Multi.insert(
        :transition,
        Transition.changeset(%Transition{}, %{
          idea_id: idea.id,
          from: idea.column,
          to: idea.column,
          actor: founder,
          note: note
        })
      )
      |> Events.add(:question_answered, idea, %{
        actor: founder,
        from: idea.column,
        to: idea.column,
        column: idea.column,
        question: %{
          "text" => question,
          "answer" => Map.get(change, :answer, current && current.answer),
          "deferred" => Map.get(change, :deferred, (current && current.deferred) || false),
          "by" => founder
        }
      })
      |> run(idea.id)
    else
      :unchanged -> {:ok, idea}
      {:error, nil} -> {:error, "That question is not on the card any more."}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Saves a founder's answer boxes of one card together (the full card sends
  them with a move, on close and on blur). `drafts` is a list of
  `{question, %{"answer" => text, "deferred" => bool}}`. A deferral that
  changed is saved first, then a typed answer. A blank box and a box equal to
  the saved answer save nothing, so the history gets no duplicate lines.
  """
  @spec save_answers(Idea.t(), String.t(), [{String.t(), map()}]) :: {:ok, Idea.t()} | error()
  def save_answers(%Idea{} = idea, founder, drafts) do
    Enum.reduce_while(drafts, {:ok, idea}, fn {q, d}, {:ok, acc} ->
      steps =
        [
          Map.has_key?(d, "deferred") && %{"deferred" => d["deferred"]},
          String.trim(to_string(d["answer"])) != "" && %{"answer" => d["answer"]}
        ]
        |> Enum.filter(& &1)

      steps
      |> Enum.reduce_while({:ok, acc}, &answer_step(&1, &2, founder, q))
      |> case do
        {:ok, i} -> {:cont, {:ok, i}}
        error -> {:halt, error}
      end
    end)
  end

  defp answer_step(attrs, {:ok, idea}, founder, question) do
    case answer_question(idea, founder, question, attrs) do
      {:ok, updated} -> {:cont, {:ok, updated}}
      error -> {:halt, error}
    end
  end

  defp answer_change(current, founder, %{"deferred" => d}, now, question) do
    deferred = d in [true, "true"]

    if (current && current.deferred) == deferred or (current == nil and not deferred),
      do: :unchanged,
      else: defer_change(deferred, founder, now, question)
  end

  defp answer_change(current, founder, %{"answer" => text}, now, question) do
    text = text |> to_string() |> String.trim()

    cond do
      text == "" ->
        {:error, "Write an answer, or defer the question."}

      current && current.answered_by == founder && current.answer == text ->
        :unchanged

      current && current.answered_by not in [nil, founder] ->
        {:error,
         "#{current.answered_by} answered this question. Only they can change the answer. Write a comment to discuss it."}

      true ->
        {:ok, %{answer: text, answered_by: founder, answered_at: now},
         "Answered: #{question} Answer: #{text}"}
    end
  end

  defp answer_change(_current, _founder, _attrs, _now, _question),
    do: {:error, "Write an answer, or defer the question."}

  defp defer_change(deferred, founder, now, question) do
    if deferred,
      do:
        {:ok, %{deferred: true, deferred_by: founder, deferred_at: now}, "Deferred: #{question}"},
      else:
        {:ok, %{deferred: false, deferred_by: nil, deferred_at: nil},
         "Open again (not deferred): #{question}"}
  end

  @doc "True when the card's PR waits for a founder's Approve (at its current head sha)."
  @spec pr_waiting?(Idea.t()) :: boolean()
  def pr_waiting?(%Idea{} = idea), do: pr_state(idea) == :awaiting

  @doc """
  The card's PR number (links loaded): the one the builder linked for approval,
  else the first `pr` link that points at a pull request; nil for none.
  """
  @spec pr_number_of(Idea.t()) :: pos_integer() | nil
  def pr_number_of(%Idea{pr_number: n}) when is_integer(n), do: n

  def pr_number_of(idea) do
    idea.links
    |> Enum.filter(&(&1.kind == "pr"))
    |> Enum.find_value(fn l ->
      case Regex.run(~r{/pull/(\d+)}, l.url) do
        [_, n] -> String.to_integer(n)
        _ -> nil
      end
    end)
  end

  # :awaiting while the card's PR (at its current head sha) has no Approve.
  defp pr_state(%Idea{pr_number: nil}), do: nil

  defp pr_state(idea) do
    approved? =
      Enum.any?(
        idea.approvals,
        &(&1.decision == "approved" and &1.pr_number == idea.pr_number and
            &1.head_sha == idea.pr_head_sha)
      )

    if approved?, do: :approved, else: :awaiting
  end

  @doc """
  Moves a card to `to` for `actor`, if `TalesForge.Board.Transitions` allows it,
  with an optional `note` for the history. Writes the transition and queues
  what the move sets off in the same transaction.
  """
  @spec move(Idea.t(), actor(), String.t(), String.t() | nil) :: {:ok, Idea.t()} | error()
  def move(%Idea{} = idea, actor, to, note \\ nil) do
    idea = get_idea!(idea.id)

    base_facts = facts(idea, note)

    facts =
      if idea.column == "building" and to == "done" and base_facts.pr_linked,
        do: Map.put(base_facts, :pr_on_prod, TalesForge.Board.OnProd.check(pr_number_of(idea))),
        else: base_facts

    with :ok <- Transitions.allowed?(team(), facts, idea.column, to, actor) do
      Multi.new()
      |> Multi.update(:idea, Idea.update_changeset(idea, %{column: to}))
      |> Multi.insert(
        :transition,
        Transition.changeset(%Transition{}, %{
          idea_id: idea.id,
          from: idea.column,
          to: to,
          actor: Transitions.actor_name(actor),
          note: note
        })
      )
      |> WorkLog.add("move", :transition, & &1.actor)
      |> add_move_events(idea, to, actor)
      |> clean_up_images(idea, to)
      |> run(idea.id)
      |> check_done_after(to == "building")
    end
  end

  # A PR link added, or a card moved to Building, after the deploy: the boot
  # run of AutoDone is over, so queue a new run now. PrBackfill also runs, so
  # an open normal-lane PR on the card waits for approval.
  defp check_done_after({:ok, %Idea{column: "building"}} = result, true) do
    TalesForge.Board.Workers.AutoDone.schedule()
    TalesForge.Board.Workers.PrBackfill.schedule()
    result
  end

  defp check_done_after(result, _), do: result

  # A card that reaches Done gives up its images (TalesForge.Images).
  defp clean_up_images(multi, idea, "done"),
    do: Multi.delete_all(multi, :images, TalesForge.Images.delete_query(idea.id))

  defp clean_up_images(multi, _idea, _to), do: multi

  # The open questions go to the inbox (Workflow.Inbox rule founder_check).
  defp check_extra(idea, extra) do
    questions = for {q, a} <- questions(idea), not Answer.settled?(a), do: q
    Map.put(extra, :questions, questions)
  end

  defp add_move_events(multi, idea, to, actor) do
    extra = %{from: idea.column, to: to, actor: Transitions.actor_name(actor)}

    case {idea.column, to} do
      {"ideas", "refining"} -> Events.add(multi, :idea_to_refining, idea, extra)
      {_, "refining"} -> Events.add(multi, :idea_back_to_refining, idea, extra)
      {_, "check"} -> Events.add(multi, :idea_to_check, idea, check_extra(idea, extra))
      {_, "building"} -> Events.add(multi, :idea_to_building, idea, extra)
      {_, "done"} -> Events.add(multi, :idea_to_done, idea, extra)
      {_, "archived"} -> Events.add(multi, :idea_to_archived, idea, extra)
      _ -> multi
    end
  end

  @doc """
  The archived cards, newest archive first (everything loaded). Votes,
  comments and history stay on them.
  """
  @spec archived() :: [Idea.t()]
  def archived do
    from(i in Idea, where: i.column == "archived")
    |> Repo.all()
    |> preload_all()
    |> Enum.sort_by(&(archived_info(&1).at || &1.updated_at), {:desc, DateTime})
  end

  @doc "The number of archived cards (the Archive tile)."
  @spec archived_count() :: non_neg_integer()
  def archived_count,
    do: Repo.aggregate(from(i in Idea, where: i.column == "archived"), :count)

  @doc """
  Who archived the card, when and why: the newest move to Archived
  (transitions loaded). All nil for a card that is not archived.
  """
  @spec archived_info(Idea.t()) :: %{
          by: String.t() | nil,
          at: DateTime.t() | nil,
          reason: String.t() | nil
        }
  def archived_info(%Idea{transitions: ts}) when is_list(ts) do
    case ts
         |> Enum.filter(&(&1.to == "archived"))
         |> Enum.max_by(& &1.inserted_at, DateTime, fn -> nil end) do
      nil -> %{by: nil, at: nil, reason: nil}
      t -> %{by: t.actor, at: t.inserted_at, reason: t.note}
    end
  end

  def archived_info(_idea), do: %{by: nil, at: nil, reason: nil}

  @doc """
  The archived cards that have all the `tags` and whose title or
  description has `query` (case-insensitive; blank matches all). Pure.

      iex> alias TalesForge.Board.Idea
      iex> cards = [%Idea{title: "Dark mode", body: "", tags: ["ui"], author: "a@x"}, %Idea{title: "Chat", body: "Dark theme for chat", tags: [], author: "a@x"}]
      iex> TalesForge.Board.filter_archived(cards, [], "dark") |> Enum.map(& &1.title)
      ["Dark mode", "Chat"]
      iex> TalesForge.Board.filter_archived(cards, ["ui"], "") |> Enum.map(& &1.title)
      ["Dark mode"]
      iex> TalesForge.Board.filter_archived(cards, [], "THEME") |> Enum.map(& &1.title)
      ["Chat"]
  """
  @spec filter_archived([Idea.t()], [String.t()], String.t() | nil) :: [map()]
  def filter_archived(cards, tags, query) do
    q = query |> to_string() |> String.trim() |> String.downcase()

    cards
    |> then(&Tags.filter(team(), &1, tags))
    |> Enum.filter(fn card ->
      q == "" or
        String.contains?(String.downcase(card.title || ""), q) or
        String.contains?(String.downcase(card.body || ""), q)
    end)
  end

  @doc """
  Archives a card in Ideas or Parked for a founder, with a short `reason`
  (necessary). Bots and the QA session cannot archive. The move is a
  transition, so it is in the card's history.
  """
  @spec archive(Idea.t(), String.t(), String.t() | nil) :: {:ok, Idea.t()} | error()
  def archive(%Idea{} = idea, founder, reason) do
    reason = reason |> to_string() |> String.trim()

    with :ok <- not_qa(founder),
         do: move(idea, actor_of(founder), "archived", if(reason == "", do: nil, else: reason))
  end

  @doc "Restores an archived card to Ideas for a founder (not a bot, not the QA session)."
  @spec restore(Idea.t(), String.t()) :: {:ok, Idea.t()} | error()
  def restore(%Idea{} = idea, founder) do
    with :ok <- not_qa(founder), do: move(idea, actor_of(founder), "ideas")
  end

  @doc """
  Deletes an archived card for good (spam or a duplicate), for a founder
  only: not a bot, not the QA session. `confirm_title` must be the
  card's title (trimmed, any case). The card's votes, comments, history and
  images go with it. A `board_deletions` row and a server log line record
  the delete.
  """
  @spec delete_archived(Idea.t(), String.t(), String.t() | nil) :: :ok | error()
  def delete_archived(%Idea{} = idea, founder, confirm_title) do
    idea = get_idea!(idea.id)

    same? = fn a, b ->
      String.downcase(String.trim(to_string(a))) == String.downcase(String.trim(b))
    end

    with :ok <- not_qa(founder),
         :ok <- Transitions.delete_allowed?(idea.column, actor_of(founder)),
         :ok <- need_title(same?.(confirm_title, idea.title)) do
      info = archived_info(idea)

      Multi.new()
      |> Multi.delete_all(:images, TalesForge.Images.delete_query(idea.id))
      |> Multi.insert(:audit, fn %{images: {n, _}} ->
        Deletion.changeset(%Deletion{}, %{
          idea_id: idea.id,
          title: String.slice(idea.title, 0, 200),
          deleted_by: normalize(founder),
          archive_reason: info.reason,
          image_count: n
        })
      end)
      |> Multi.delete(:idea, idea)
      |> Repo.transaction()
      |> case do
        {:ok, %{images: {n, _}}} ->
          Logger.notice(
            "board: card #{idea.id} (#{inspect(idea.title)}) deleted from the archive by " <>
              "#{normalize(founder)} with #{n} image(s)"
          )

          broadcast()
          :ok

        {:error, _step, reason, _} ->
          {:error, if(is_binary(reason), do: reason, else: inspect(reason))}
      end
    end
  end

  @doc "The audit records of the deletes, newest first."
  @spec deletions() :: [Deletion.t()]
  def deletions, do: Repo.all(from(d in Deletion, order_by: [desc: d.inserted_at]))

  defp need_title(true), do: :ok
  defp need_title(false), do: {:error, "Type the title of the card to confirm the delete."}

  defp not_qa(who) do
    if normalize(to_string(who)) == TalesForge.QaLogin.email(),
      do: {:error, TalesForge.QaLogin.refused_message()},
      else: :ok
  end

  @doc "Records the decision log commit of a card (set once; idempotent)."
  @spec record_decision(Idea.t(), String.t(), String.t(), String.t()) :: {:ok, Idea.t()} | error()
  def record_decision(%Idea{} = idea, slug, sha, url) do
    idea = get_idea!(idea.id)

    if idea.decision_sha do
      {:ok, idea}
    else
      Multi.new()
      |> Multi.update(
        :idea,
        Idea.update_changeset(idea, %{decision_sha: sha, decision_slug: slug})
      )
      |> Multi.insert(
        :link,
        Link.changeset(%Link{}, %{
          idea_id: idea.id,
          kind: "decision",
          url: url,
          label: "Decision log",
          added_by: "board"
        }),
        on_conflict: :nothing
      )
      |> Multi.insert(
        :transition,
        Transition.changeset(%Transition{}, %{
          idea_id: idea.id,
          from: idea.column,
          to: idea.column,
          actor: "board",
          note: "Decision log entry written: #{sha}"
        })
      )
      |> run(idea.id)
    end
  end

  @doc """
  Imports the open Collab decisions (`/admin/founders/decisions`, status open
  or discussing) as Ideas, once each (`collab_decision_id`), with their
  comments. Afterwards the decision queue is read-only
  (`TalesForge.Collab.read_only?/0`). Returns how many were imported.
  """
  @spec import_collab() :: {:ok, non_neg_integer()}
  def import_collab do
    imported =
      from(i in Idea, where: not is_nil(i.collab_decision_id), select: i.collab_decision_id)

    decisions =
      from(d in Decision,
        where: d.status in ["open", "discussing"] and d.id not in subquery(imported),
        order_by: [asc: d.rank, asc: d.slug],
        preload: [:comments]
      )
      |> Repo.all()

    Repo.transaction(fn ->
      Enum.each(decisions, &import_decision/1)
    end)

    broadcast()
    {:ok, length(decisions)}
  end

  defp import_decision(decision) do
    body =
      [
        decision.body,
        options(decision.options),
        "Imported from the decision queue (#{decision.slug})."
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join("\n\n")

    idea =
      %Idea{}
      |> Idea.create_changeset(%{
        title: String.slice(decision.title, 0, 160),
        body: body,
        author: "import",
        collab_decision_id: decision.id
      })
      |> Repo.insert!()

    Repo.insert!(
      Transition.changeset(%Transition{}, %{
        idea_id: idea.id,
        to: "ideas",
        actor: "import",
        note: "From the decision queue: #{decision.slug}"
      })
    )

    Enum.each(decision.comments, fn c ->
      Repo.insert!(
        Comment.changeset(%Comment{}, %{idea_id: idea.id, author: c.author_email, body: c.body})
      )
    end)
  end

  defp options([]), do: nil
  defp options(options), do: "Options:\n" <> Enum.map_join(options, "\n", &("- " <> &1))

  @doc "True once the open Collab decisions have been imported."
  @spec collab_imported?() :: boolean()
  def collab_imported?, do: TalesForge.Collab.read_only?()

  @doc """
  The builder puts a PR up for a founder's merge OK (decision 2026-10-10; only
  normal-lane PRs, fast-lane PRs need no OK). `attrs`: `number`, `url`,
  `head_sha`, `player_note` (one line: what changes for players), and either
  `idea_id` (an existing card) or `title` (a new card, which the builder makes in
  Building). The card gets the PR fields and a `pr` link and stays in
  Building with "PR waiting for approval" (decision 2026-10-10, 15:08), with a
  line in the move log.

  Linking the same PR again updates the head sha and the note ("approve once",
  decision 2026-10-10):

  - Before any answer: one line "New commit <sha>" in the history. The card
    keeps its one approval request.
  - After an Approve: the approval is kept for the new head sha (a new
    `TalesForge.Board.Approval` row for the same founder), the history gets
    "New commit <sha> after approval; approval kept", and the builder gets
    `pr.approved` again with the newest head, so the merge uses that head.
  - With `player_change: true` (the change alters what the PR does for
    players), or after Request changes: the PR waits for a founder's OK
    again.
  """
  @spec link_pr(map()) :: {:ok, Idea.t()} | error()
  def link_pr(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    with {:ok, number} <- pr_number(attrs["number"]),
         :ok <- need_text(attrs["url"], "url"),
         :ok <- need_text(attrs["head_sha"], "head_sha"),
         :ok <- need_text(attrs["player_note"], "player_note"),
         {:ok, idea} <- pr_card(attrs, number) do
      idea |> put_pr(number, attrs) |> check_done_after(true)
    end
  end

  defp pr_number(n) when is_integer(n) and n > 0, do: {:ok, n}

  defp pr_number(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, ""} when i > 0 -> {:ok, i}
      _ -> {:error, "number must be the PR number."}
    end
  end

  defp pr_number(_), do: {:error, "number must be the PR number."}

  defp need_text(v, name) do
    if is_binary(v) and String.trim(v) != "", do: :ok, else: {:error, "#{name} is required."}
  end

  defp pr_card(%{"idea_id" => id}, _number) when is_binary(id) and id != "" do
    case get_idea(id) do
      nil -> {:error, "No such card."}
      idea -> {:ok, idea}
    end
  end

  defp pr_card(attrs, number) do
    case Repo.one(from i in Idea, where: i.pr_number == ^number, limit: 1) do
      %Idea{} = idea ->
        {:ok, get_idea!(idea.id)}

      nil ->
        title = attrs["title"] |> to_string() |> String.trim()
        title = if title == "", do: "PR ##{number}", else: title
        create_building_card(title, attrs["player_note"])
    end
  end

  # The builder builds a PR that has no card yet: a new card, made in Building.
  defp create_building_card(title, body) do
    Multi.new()
    |> Multi.insert(
      :idea,
      Idea.create_changeset(%Idea{}, %{
        "title" => title,
        "body" => body,
        "author" => Team.actor(team(), :builder)
      })
    )
    |> Multi.update(:building, fn %{idea: idea} ->
      Idea.update_changeset(idea, %{column: "building"})
    end)
    |> Multi.insert(:transition, fn %{idea: idea} ->
      Transition.changeset(%Transition{}, %{
        idea_id: idea.id,
        to: "building",
        actor: Team.actor(team(), :builder),
        note: "#{Team.bot_name(team(), :builder)} made this card for a PR."
      })
    end)
    |> run()
  end

  # The card stays in Building; the PR waits for a founder's OK there.
  defp put_pr(%Idea{column: "building"} = idea, number, attrs),
    do: write_pr(idea, number, attrs)

  defp put_pr(idea, _number, _attrs),
    do:
      {:error,
       "#{Team.bot_name(team(), :builder)} links a PR to a card in Building. This card is in #{Transitions.label(team(), idea.column)}."}

  defp write_pr(idea, number, attrs) do
    note = String.trim(attrs["player_note"])
    sha = String.trim(attrs["head_sha"])
    relink = relink(idea, number, sha, attrs["player_change"] in [true, "true"])

    Multi.new()
    |> Multi.update(
      :idea,
      Idea.update_changeset(idea, %{
        pr_number: number,
        pr_url: attrs["url"],
        pr_head_sha: sha,
        player_note: note
      })
    )
    |> Multi.insert(:transition, fn _ ->
      Transition.changeset(%Transition{}, %{
        idea_id: idea.id,
        from: idea.column,
        to: idea.column,
        actor: Team.actor(team(), :builder),
        note: relink_note(relink, number, sha, note)
      })
    end)
    |> keep_approval(relink, idea, number, attrs["url"], sha)
    |> pr_waiting(relink in [:request, :new_commit], idea, number, attrs["url"], sha, note)
    |> then(fn multi ->
      if Enum.any?(idea.links, &(&1.kind == "pr" and &1.url == attrs["url"])),
        do: multi,
        else:
          Multi.insert(
            multi,
            :link,
            Link.changeset(%Link{}, %{
              idea_id: idea.id,
              kind: "pr",
              url: attrs["url"],
              label: "PR ##{number}",
              added_by: Team.actor(team(), :builder)
            })
          )
    end)
    |> run(idea.id)
  end

  # What a link of PR `number` at `sha` means for the card's approval:
  # :request (a new request), :new_commit (same PR, no answer yet),
  # {:kept, approval} (approved before; the approval stays), :same (same
  # sha, approved).
  defp relink(%Idea{pr_number: number} = idea, number, sha, player_change?) do
    latest =
      idea.approvals
      |> Enum.filter(&(&1.pr_number == number))
      |> Enum.max_by(& &1.inserted_at, DateTime, fn -> nil end)

    case latest do
      nil -> :new_commit
      %Approval{decision: "approved"} when player_change? -> :request
      %Approval{decision: "approved", head_sha: ^sha} -> :same
      %Approval{decision: "approved"} = approval -> {:kept, approval}
      _ -> :request
    end
  end

  defp relink(_idea, _number, _sha, _player_change?), do: :request

  defp relink_note(:request, number, sha, note),
    do: "PR ##{number} (#{short(sha)}) waits for a founder's OK: #{note}"

  defp relink_note(:new_commit, number, sha, _note),
    do: "New commit #{short(sha)} on PR ##{number}."

  defp relink_note(:same, number, sha, _note),
    do: "PR ##{number} (#{short(sha)}) linked again; approval kept."

  defp relink_note({:kept, _}, _number, sha, _note),
    do: "New commit #{short(sha)} after approval; approval kept."

  # The approval stays with the newest head: a new approval row for the same
  # founder, and pr.approved wakes the builder with the newest head for the merge.
  defp keep_approval(multi, {:kept, approval}, idea, number, url, sha) do
    multi
    |> Multi.insert(
      :approval,
      Approval.changeset(%Approval{}, %{
        idea_id: idea.id,
        decision: "approved",
        founder: approval.founder,
        pr_number: number,
        head_sha: sha,
        comment: "Approval kept after new commit #{short(sha)}."
      })
    )
    |> Events.add(:pr_approved, idea, %{
      actor: approval.founder,
      from: idea.column,
      to: idea.column,
      pr: %{"number" => number, "url" => url, "head_sha" => sha},
      approver: approval.founder,
      comment: "Approval kept after new commit #{short(sha)}."
    })
  end

  defp keep_approval(multi, _relink, _idea, _number, _url, _sha), do: multi

  # A PR that waits for a founder's OK goes to the inbox (Workflow.Inbox rule
  # pr_approval) as an approve item.
  defp pr_waiting(multi, false, _idea, _number, _url, _sha, _note), do: multi

  defp pr_waiting(multi, true, idea, number, url, sha, note),
    do:
      Events.add(multi, :pr_waiting, idea, %{
        actor: Team.actor(team(), :builder),
        from: idea.column,
        to: idea.column,
        note: note,
        pr: %{"number" => number, "url" => url, "head_sha" => sha}
      })

  @doc """
  Marks the open PR `number` (head `head_sha`, at `url`) on a Building card as
  waiting for a founder's OK, for a PR that came to the card as a plain `pr`
  link, not through `link_pr/1`. `TalesForge.Board.Workers.PrBackfill` calls
  this after GitHub tells that the PR is open, not merged, and in the normal
  lane. The card then shows "PR waiting for approval" with Approve and Request
  changes, the same as after `link_pr/1`. A line goes in the move log. The
  card keeps its player note.
  """
  @spec mark_pr_waiting(Idea.t(), pos_integer(), String.t(), String.t()) ::
          {:ok, Idea.t()} | error()
  def mark_pr_waiting(%Idea{column: "building"} = idea, number, url, head_sha)
      when is_integer(number) and number > 0 and is_binary(url) and is_binary(head_sha) do
    Multi.new()
    |> Multi.update(
      :idea,
      Idea.update_changeset(idea, %{pr_number: number, pr_url: url, pr_head_sha: head_sha})
    )
    |> Multi.insert(:transition, fn _ ->
      Transition.changeset(%Transition{}, %{
        idea_id: idea.id,
        from: idea.column,
        to: idea.column,
        actor: "bot:board",
        note: "PR ##{number} (#{short(head_sha)}) waits for a founder's OK."
      })
    end)
    |> pr_waiting(true, idea, number, url, head_sha, idea.player_note)
    |> run(idea.id)
  end

  def mark_pr_waiting(%Idea{} = idea, _number, _url, _head_sha),
    do:
      {:error,
       "A PR waits for approval on a card in Building. This card is in #{Transitions.label(team(), idea.column)}."}

  @doc """
  A founder answers the PR on a card: `:approve` or `:request_changes`, with
  an optional `comment`. Records who, when, the PR number and its head sha
  (`TalesForge.Board.Approval`), writes a line in the history and wakes the builder
  (`pr.approved` / `pr.changes_requested`). Approving also moves the card from
  Founder check to Building (`TalesForge.Board.Transitions`: Approve is the
  gate). Request changes keeps the card in Founder check.
  """
  @spec answer_pr(Idea.t(), String.t(), :approve | :request_changes, String.t() | nil) ::
          {:ok, Idea.t()} | error()
  def answer_pr(%Idea{pr_number: nil}, _founder, _answer, _comment),
    do: {:error, "No PR waits on this card."}

  def answer_pr(%Idea{} = idea, founder, answer, comment)
      when answer in [:approve, :request_changes] do
    idea = get_idea!(idea.id)
    founder = normalize(founder)
    comment = comment |> to_string() |> String.trim()
    approve? = answer == :approve
    to = idea.column

    with :ok <- answer_allowed(idea, founder, approve?) do
      decision = if approve?, do: "approved", else: "changes_requested"
      label = if approve?, do: "Approved", else: "Changes requested on"

      extra = %{
        actor: founder,
        from: idea.column,
        to: to,
        pr: %{
          "number" => idea.pr_number,
          "url" => idea.pr_url,
          "head_sha" => idea.pr_head_sha
        },
        approver: founder,
        comment: comment
      }

      Multi.new()
      |> Multi.insert(
        :approval,
        Approval.changeset(%Approval{}, %{
          idea_id: idea.id,
          decision: decision,
          founder: founder,
          pr_number: idea.pr_number,
          head_sha: idea.pr_head_sha,
          comment: comment
        })
      )
      |> Multi.insert(
        :transition,
        Transition.changeset(%Transition{}, %{
          idea_id: idea.id,
          from: idea.column,
          to: to,
          actor: founder,
          note:
            "#{label} PR ##{idea.pr_number} (#{short(idea.pr_head_sha)})" <>
              if(comment == "", do: "", else: ": " <> comment)
        })
      )
      |> Events.add(if(approve?, do: :pr_approved, else: :pr_changes_requested), idea, extra)
      |> run(idea.id)
    end
  end

  defp answer_allowed(idea, founder, _approve?),
    do: Transitions.pr_answer(team(), facts(idea), idea.column, actor_of(founder))

  defp actor_of("bot:" <> bot), do: {:bot, bot}
  defp actor_of(founder), do: {:founder, founder}

  defp short(nil), do: "no sha"
  defp short(sha) when not is_binary(sha), do: "no sha"
  defp short(sha), do: String.slice(sha, 0, 7)

  defp run(multi, idea_id \\ nil) do
    case Repo.transaction(multi) do
      {:ok, changes} ->
        broadcast()
        id = idea_id || changes[:idea].id
        {:ok, get_idea!(id)}

      {:error, _step, %Ecto.Changeset{} = changeset, _} ->
        {:error, changeset}

      {:error, _step, reason, _} when is_binary(reason) ->
        {:error, reason}

      {:error, _step, reason, _} ->
        {:error, inspect(reason)}
    end
  end

  defp after_update({:ok, idea}) do
    broadcast()
    {:ok, get_idea!(idea.id)}
  end

  defp after_update(error), do: error

  defp broadcast, do: Phoenix.PubSub.broadcast(TalesForge.PubSub, @topic, {:board, :changed})

  defp normalize("bot:" <> _ = bot), do: bot
  defp normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()

  # The team config: this module is an edge (it does IO).
  defp team, do: Workflow.Team.Source.team()
end
