defmodule TalesForge.Chat.ThreadRules do
  @moduledoc """
  The pure rules of the chat threads (`TalesForge.Chat.Thread`). No IO: the
  team config (`Workflow.Team`) is an argument. `TalesForge.Chat` calls
  these rules at the edge, on each read, post, PubSub path and unread count.

  A viewer is the actor that reads or posts:

  - `{:founder, handle}`: a founder, from the GitHub login of the session.
  - `{:bot, id}`: a bot of the team config.
  - `:guest`: a signed-in team member with no founder handle.
  - `:nobody`: an unknown actor. The rules give it no access.

  The access rule is one function, `can_read?/2`. A post, a PubSub topic
  and an unread count use the same rule:

  - Each known viewer can read a subject thread.
  - Only the two members can read a direct thread. A bot can never read a
    direct thread.
  """

  alias TalesForge.Chat.Thread
  alias Workflow.Team

  @type viewer :: {:founder, String.t()} | {:bot, atom()} | :guest | :nobody

  @topic "team_chat"

  @doc """
  The viewer of an author (a founder email or `bot:<id>`) with the GitHub
  `login` of the session. A founder author with no handle is a guest.

      iex> team = Workflow.Team.example()
      iex> TalesForge.Chat.ThreadRules.viewer(team, "ada@example.com", "ada-gh")
      {:founder, "ada"}
      iex> TalesForge.Chat.ThreadRules.viewer(team, "x@example.com", nil)
      :guest
      iex> TalesForge.Chat.ThreadRules.viewer(team, "bot:nobot", nil)
      :nobody
  """
  @spec viewer(Team.t(), String.t() | nil, String.t() | nil) :: viewer()
  def viewer(%Team{} = team, "bot:" <> _ = author, _login) do
    case Team.bot_id(team, author) do
      nil -> :nobody
      id -> {:bot, id}
    end
  end

  def viewer(%Team{} = team, author, login) when is_binary(author) do
    team
    |> founder_handle(login)
    |> case do
      nil -> if String.contains?(author, "@"), do: :guest, else: :nobody
      handle -> {:founder, handle}
    end
  end

  def viewer(%Team{} = team, nil, login) do
    case founder_handle(team, login) do
      nil -> :nobody
      handle -> {:founder, handle}
    end
  end

  defp founder_handle(team, login) when is_binary(login),
    do: Map.get(Team.github_handles(team), login |> String.trim() |> String.downcase())

  defp founder_handle(_team, _login), do: nil

  @doc """
  True when `viewer` can read `thread`. Posts use the same rule.

      iex> alias TalesForge.Chat.{Thread, ThreadRules}
      iex> direct = %Thread{kind: "direct", members: ["ada", "lin"]}
      iex> ThreadRules.can_read?(direct, {:founder, "ada"})
      true
      iex> ThreadRules.can_read?(direct, {:founder, "orjan"})
      false
      iex> ThreadRules.can_read?(direct, {:bot, :rita})
      false
      iex> ThreadRules.can_read?(%Thread{kind: "subject"}, {:bot, :rita})
      true
  """
  @spec can_read?(Thread.t(), viewer()) :: boolean()
  def can_read?(%Thread{kind: "subject"}, {:founder, handle}) when is_binary(handle), do: true

  def can_read?(%Thread{kind: "subject"}, {:bot, id}) when is_atom(id) and not is_nil(id),
    do: true

  def can_read?(%Thread{kind: "subject"}, :guest), do: true

  def can_read?(%Thread{kind: "direct", members: [_, _] = members}, {:founder, handle})
      when is_binary(handle),
      do: handle in members

  def can_read?(_thread, _viewer), do: false

  @doc "True when `viewer` can post in `thread`: the same rule as `can_read?/2`."
  @spec can_post?(Thread.t(), viewer()) :: boolean()
  def can_post?(thread, viewer), do: can_read?(thread, viewer)

  @doc """
  The fields of a new subject thread. Founders and bots can start one.

      iex> TalesForge.Chat.ThreadRules.subject_attrs({:bot, :rita}, "Release", ~U[2026-10-13 10:00:00Z])
      {:ok, %{kind: "subject", subject: "Release", members: [], created_by: "bot:rita", last_message_at: ~U[2026-10-13 10:00:00Z]}}
      iex> TalesForge.Chat.ThreadRules.subject_attrs(:guest, "Release", ~U[2026-10-13 10:00:00Z])
      {:error, :forbidden}
  """
  @spec subject_attrs(viewer(), String.t() | nil, DateTime.t()) ::
          {:ok, map()} | {:error, :forbidden}
  def subject_attrs({:founder, handle}, subject, now) when is_binary(handle),
    do: {:ok, new_attrs("subject", subject, [], handle, now)}

  def subject_attrs({:bot, id}, subject, now) when is_atom(id) and not is_nil(id),
    do: {:ok, new_attrs("subject", subject, [], "bot:#{id}", now)}

  def subject_attrs(_viewer, _subject, _now), do: {:error, :forbidden}

  @doc """
  The fields of a new direct thread between the founder `viewer` and the
  founder `other` (a handle of the team config). Only a founder can start
  one, with one other founder.

      iex> team = Workflow.Team.example()
      iex> {:ok, attrs} = TalesForge.Chat.ThreadRules.direct_attrs(team, {:founder, "lin"}, "ada", ~U[2026-10-13 10:00:00Z])
      iex> attrs.members
      ["ada", "lin"]
      iex> TalesForge.Chat.ThreadRules.direct_attrs(team, {:founder, "ada"}, "ada", ~U[2026-10-13 10:00:00Z])
      {:error, :forbidden}
      iex> TalesForge.Chat.ThreadRules.direct_attrs(team, {:bot, :rita}, "ada", ~U[2026-10-13 10:00:00Z])
      {:error, :forbidden}
  """
  @spec direct_attrs(Team.t(), viewer(), String.t() | nil, DateTime.t()) ::
          {:ok, map()} | {:error, :forbidden}
  def direct_attrs(%Team{} = team, {:founder, me}, other, now)
      when is_binary(me) and is_binary(other) and me != other do
    handles = Team.handles(team)

    if me in handles and other in handles,
      do: {:ok, new_attrs("direct", "1:1", direct_members(me, other), me, now)},
      else: {:error, :forbidden}
  end

  def direct_attrs(_team, _viewer, _other, _now), do: {:error, :forbidden}

  @doc """
  The members of the direct thread of two founders, sorted. One pair has
  one direct thread.

      iex> TalesForge.Chat.ThreadRules.direct_members("lin", "ada")
      ["ada", "lin"]
  """
  @spec direct_members(String.t(), String.t()) :: [String.t()]
  def direct_members(a, b), do: Enum.sort([a, b])

  defp new_attrs(kind, subject, members, created_by, now),
    do: %{
      kind: kind,
      subject: subject,
      members: members,
      created_by: created_by,
      last_message_at: now
    }

  @doc """
  The founder handles of a message that get a mention in `thread`. In a
  direct thread only the members get a mention.

      iex> alias TalesForge.Chat.{Thread, ThreadRules}
      iex> ThreadRules.mentions(%Thread{kind: "direct", members: ["ada", "lin"]}, ["lin", "orjan"])
      ["lin"]
      iex> ThreadRules.mentions(%Thread{kind: "subject"}, ["lin", "orjan"])
      ["lin", "orjan"]
  """
  @spec mentions(Thread.t(), [String.t()]) :: [String.t()]
  def mentions(%Thread{kind: "subject"}, handles), do: handles

  def mentions(%Thread{kind: "direct", members: members}, handles),
    do: handles -- (handles -- members)

  @doc """
  The bots that a message in `thread` wakes. A message in a direct thread
  wakes no bot, because a bot cannot read it.

      iex> alias TalesForge.Chat.{Thread, ThreadRules}
      iex> ThreadRules.wakes(%Thread{kind: "direct", members: ["ada", "lin"]}, [:rita])
      []
      iex> ThreadRules.wakes(%Thread{kind: "subject"}, [:rita])
      [:rita]
  """
  @spec wakes(Thread.t(), [atom()]) :: [atom()]
  def wakes(%Thread{kind: "subject"}, bots), do: bots
  def wakes(_thread, _bots), do: []

  @doc """
  The PubSub topics of `thread`. A subject thread uses the shared topic. A
  direct thread uses one topic for each member, and no other topic.

      iex> alias TalesForge.Chat.{Thread, ThreadRules}
      iex> ThreadRules.topics(%Thread{kind: "direct", members: ["ada", "lin"]})
      ["team_chat:direct:ada", "team_chat:direct:lin"]
      iex> ThreadRules.topics(%Thread{kind: "subject"})
      ["team_chat"]
  """
  @spec topics(Thread.t()) :: [String.t()]
  def topics(%Thread{kind: "subject"}), do: [@topic]
  def topics(%Thread{kind: "direct", members: members}), do: Enum.map(members, &direct_topic/1)

  @doc """
  The PubSub topics that `viewer` can subscribe to.

      iex> TalesForge.Chat.ThreadRules.viewer_topics({:founder, "ada"})
      ["team_chat", "team_chat:direct:ada"]
      iex> TalesForge.Chat.ThreadRules.viewer_topics({:bot, :rita})
      ["team_chat"]
      iex> TalesForge.Chat.ThreadRules.viewer_topics(:nobody)
      []
  """
  @spec viewer_topics(viewer()) :: [String.t()]
  def viewer_topics({:founder, handle}) when is_binary(handle), do: [@topic, direct_topic(handle)]
  def viewer_topics(:nobody), do: []
  def viewer_topics(_viewer), do: [@topic]

  defp direct_topic(handle), do: "#{@topic}:direct:#{handle}"

  @doc """
  The threads that `viewer` can read, newest message first. The thread
  list and the unread counts use this filter.
  """
  @spec visible([Thread.t()], viewer()) :: [Thread.t()]
  def visible(threads, viewer) do
    threads
    |> Enum.filter(&can_read?(&1, viewer))
    |> Enum.sort_by(& &1.last_message_at, {:desc, DateTime})
  end

  @doc """
  The other member of a direct thread for the founder `viewer`, or nil.

      iex> alias TalesForge.Chat.{Thread, ThreadRules}
      iex> ThreadRules.other_member(%Thread{kind: "direct", members: ["ada", "lin"]}, {:founder, "ada"})
      "lin"
  """
  @spec other_member(Thread.t(), viewer()) :: String.t() | nil
  def other_member(%Thread{kind: "direct", members: members}, {:founder, me}),
    do: members |> List.delete(me) |> List.first()

  def other_member(_thread, _viewer), do: nil
end
