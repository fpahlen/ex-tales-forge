defmodule TalesForge.Online.Founders do
  @moduledoc """
  The founder list that `TalesForge.Online` and `TalesForge.Online.Peer`
  share: the entry type, the check for entries from Presence or from the
  other app, and the "the other app's list changed" broadcast. A leaf, so
  Peer does not call back into Online.
  """

  @changed_topic "online:changed"

  @typedoc "One founder on one app."
  @type t :: %{
          email: String.t(),
          page: String.t(),
          app: String.t(),
          since: DateTime.t()
        }

  @doc "The PubSub topic of `broadcast_changed/0`."
  @spec changed_topic() :: String.t()
  def changed_topic, do: @changed_topic

  @doc "Tells subscribers (`TalesForge.Online.subscribe/0`) that the other app's list changed."
  @spec broadcast_changed() :: :ok
  def broadcast_changed,
    do: Phoenix.PubSub.broadcast(TalesForge.PubSub, @changed_topic, {:online, :changed})

  @doc """
  Validates entries from the other app (or from `TalesForge.Online.local/0`) into `t:t/0`.
  Entries with a missing field are left out.

      iex> TalesForge.Online.Founders.normalize([%{"email" => "a@x.se", "page" => "Docs",
      ...>   "app" => "playtest", "since" => "2026-10-10T12:00:00Z"}, %{"email" => 1}])
      [%{email: "a@x.se", login: nil, page: "Docs", app: "playtest", since: ~U[2026-10-10 12:00:00Z]}]
  """
  @spec normalize(term()) :: [t()]
  def normalize(list) when is_list(list), do: Enum.flat_map(list, &entry/1)
  def normalize(_), do: []

  defp entry(%{"email" => e, "page" => p, "app" => a, "since" => s} = m)
       when is_binary(e) and is_binary(p) and is_binary(a) and is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, since, _} ->
        [%{email: e, login: login(m["login"]), page: p, app: a, since: since}]

      _ ->
        []
    end
  end

  defp entry(_), do: []

  defp login(login) when is_binary(login) and login != "", do: String.downcase(login)
  defp login(_), do: nil
end
