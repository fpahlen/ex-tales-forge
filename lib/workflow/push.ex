defmodule Workflow.Push do
  @moduledoc """
  Web push for the installed team app (decision 2026-10-14 "Install the team
  page as an app (PWA)").

  - The team page (`TalesForgeWeb.TeamLive`) asks the browser for
    notification permission one time. After the founder gives permission,
    the browser makes a subscription, and `subscribe/2` stores it.
  - `push_subscriptions` has one row for each founder and browser profile
    (`Workflow.Push.Subscription`). The endpoint is the key.
  - The server sends a push when it creates an inbox item for a founder
    (`Workflow.Inbox.Store`). A chat message that the inbox rules route to a
    founder makes an inbox item, so it sends a push too. The item and the
    job go into the same transaction (`job/1`, `Workflow.Push.Worker`).
  - The push service gives 404 or 410 for a subscription that the browser
    removed. Then `deliver/1` deletes the row.
  - The VAPID keys are the secrets `WEB_PUSH_VAPID_PUBLIC_KEY` and
    `WEB_PUSH_VAPID_PRIVATE_KEY` (config `:web_push_ex, :vapid`, read in
    `config/runtime.exs`). The VAPID subject is the team page URL (`subject/0`). Without them, push is off: `enabled?/0` is false,
    and the server makes no push jobs.
  - The library `web_push_ex` encrypts the message (RFC 8291, aes128gcm)
    and signs the VAPID token. The HTTP client is `Workflow.Push.Http`
    (config `:ex_tales_forge, Workflow.Push, client:`).

  This module does IO, so it is an edge.
  """

  import Ecto.Query

  alias TalesForge.Workflow.Repo
  alias Workflow.Inbox.Record
  alias Workflow.Push.{Subscription, Worker}

  @typedoc "The JSON message that the service worker shows (`priv/static/team-sw.js`)."
  @type message :: %{title: String.t(), body: String.t(), url: String.t(), tag: String.t()}

  @typedoc "The result of one send."
  @type result :: :sent | :expired | {:error, term()}

  @body_max 180

  @doc "True when the VAPID keys are set. Push is on only then."
  @spec enabled?() :: boolean()
  def enabled? do
    vapid = Application.get_env(:web_push_ex, :vapid, [])
    Enum.all?([:public_key, :private_key], &present?(vapid[&1]))
  end

  @doc """
  The VAPID subject: the team page URL of this app (`TalesForge.AppRole`).
  A local app uses the production URL.
  """
  @spec subject() :: String.t()
  def subject do
    app = if TalesForge.AppRole.role() == :playtest, do: :playtest, else: :production
    TalesForge.AppRole.base_url(app) <> "/team"
  end

  # web_push_ex reads the subject from its config. Put it there one time.
  defp put_subject do
    vapid = Application.get_env(:web_push_ex, :vapid, [])

    unless present?(vapid[:subject]),
      do: Application.put_env(:web_push_ex, :vapid, Keyword.put(vapid, :subject, subject()))
  end

  defp present?(value), do: is_binary(value) and value != ""

  @doc "The VAPID public key for `pushManager.subscribe/1`, or nil when push is off."
  @spec public_key() :: String.t() | nil
  def public_key, do: if(enabled?(), do: Application.get_env(:web_push_ex, :vapid)[:public_key])

  @doc """
  Stores the subscription of `handle` from the browser JSON
  (`endpoint`, `keys.p256dh`, `keys.auth`). A known endpoint gets the new
  handle and keys, so one browser profile keeps one row.
  """
  @spec subscribe(String.t(), map()) :: {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def subscribe(handle, %{} = json) do
    keys = json["keys"] || %{}

    attrs = %{
      handle: handle,
      endpoint: json["endpoint"],
      p256dh: keys["p256dh"],
      auth: keys["auth"],
      user_agent: json["user_agent"] && String.slice(json["user_agent"], 0, 255)
    }

    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:handle, :p256dh, :auth, :user_agent, :updated_at]},
      conflict_target: :endpoint,
      returning: true
    )
  end

  @doc "The subscriptions of `handle`, oldest first."
  @spec subscriptions(String.t()) :: [Subscription.t()]
  def subscriptions(handle),
    do:
      Repo.all(from s in Subscription, where: s.handle == ^handle, order_by: [asc: s.inserted_at])

  @doc """
  The job that sends the push of the inbox item `record`, or nil when push is
  off. `Workflow.Inbox.Store` inserts it in the transaction of the item.
  """
  @spec job(Record.t()) :: Oban.Job.changeset() | nil
  def job(%Record{id: id}) when is_binary(id),
    do: if(enabled?(), do: Worker.new(%{"item_id" => id}))

  def job(_record), do: nil

  @doc """
  The message of the inbox item `record`: a chat item says "New chat
  message", any other item says "New inbox item".

      iex> Workflow.Push.message(%Workflow.Inbox.Record{id: "i1", source: :chat, author: "ada", title: "General", body: "Look at this", url: "/team#chat"})
      %{title: "New chat message", body: "ada in General: Look at this", url: "/team#chat", tag: "inbox-i1"}
      iex> Workflow.Push.message(%Workflow.Inbox.Record{id: "i2", source: :pr, author: nil, title: "PR #12 waits for your OK", body: "", url: nil})
      %{title: "New inbox item", body: "PR #12 waits for your OK", url: "/team", tag: "inbox-i2"}
  """
  @spec message(Record.t()) :: message()
  def message(%Record{} = r) do
    head = Enum.join(Enum.reject([r.author, r.title], &blank?/1), " in ")
    text = Enum.join(Enum.reject([head, r.body], &blank?/1), ": ")

    %{
      title: if(r.source == :chat, do: "New chat message", else: "New inbox item"),
      body: String.slice(text, 0, @body_max),
      url: if(blank?(r.url), do: "/team", else: r.url),
      tag: "inbox-" <> r.id
    }
  end

  defp blank?(value), do: value in [nil, ""]

  @doc """
  Sends the push of the inbox item `item_id` to each subscription of its
  recipient. Deletes each subscription that the push service gives as
  expired. Gives the result of each send.
  """
  @spec deliver(String.t()) :: [result()]
  def deliver(item_id) do
    case Repo.get(Record, item_id) do
      %Record{state: "new"} = record ->
        payload = record |> message() |> Jason.encode!()
        Enum.map(subscriptions(record.recipient), &send_one(&1, payload))

      _closed_or_gone ->
        []
    end
  end

  @doc """
  Sends `message` to each subscription of `handle`. Use it to test push
  from a console.
  """
  @spec send_to(String.t(), message()) :: [result()]
  def send_to(handle, %{} = message) do
    payload = Jason.encode!(message)
    Enum.map(subscriptions(handle), &send_one(&1, payload))
  end

  defp send_one(%Subscription{} = sub, payload) do
    put_subject()

    request =
      WebPushEx.request(
        %WebPushEx.Subscription{
          endpoint: URI.parse(sub.endpoint),
          keys: %{p256dh: sub.p256dh, auth: sub.auth}
        },
        payload
      )

    case client().post(request) do
      {:ok, status} when status in 200..299 ->
        Repo.update_all(from(s in Subscription, where: s.id == ^sub.id),
          set: [last_sent_at: DateTime.utc_now()]
        )

        :sent

      {:ok, status} when status in [404, 410] ->
        Repo.delete_all(from(s in Subscription, where: s.id == ^sub.id))
        :expired

      {:ok, status} ->
        {:error, {:status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp client,
    do: Application.get_env(:ex_tales_forge, __MODULE__, [])[:client] || Workflow.Push.Http
end
