defmodule TalesForge.QaLogin do
  @moduledoc """
  The QA sign-in for Gentry (the QA bot) on `/team` and `/team/presentation`:
  a read-only identity, "Gentry (QA)", separate from the founders' GitHub
  sign-in (`TalesForge.AdminAuth`).

  - Gentry gives its own secret token at `/team/qa-login`
    (`TalesForgeWeb.QaLoginController`). A correct token starts a normal
    browser session. The token is never kept in the session: the session
    holds an HMAC tag of the token, and each request compares that tag with
    the tag of the configured token (`valid_session?/1`). When the secret
    changes or goes, every QA session stops at the next request.
  - The token is the Fly secret GENTRY_QA_TOKEN (same value on production and
    playtest; tales-forge-docs `docs/fly-secrets.md`). Unset or blank: the QA
    sign-in is off and `/team/qa-login` answers 404.
  - The token compare is timing safe (`Plug.Crypto.secure_compare/2` on
    SHA-256 digests, so the length does not leak either).
  - The QA session can open the `/team` pages only (`allowed_path?/1`,
    `allowed_view?/1`). It is read-only: every write is refused on the server
    (`read_only?/0`, `read_event?/1`). It does not show in "Online now" and it
    never marks pings or chat messages as read.
  - QA_ALLOW_WRITES=true lets the QA session write, on playtest only, for
    later tests of the write paths. It is off by default, and production
    ignores it (`read_only?/0`).
  """

  alias TalesForge.AppRole

  @identity_key "qa_identity"
  @tag_key "qa_token_tag"
  @identity "gentry"

  @email "gentry-qa@qa.tales-forge.invalid"
  @name "Gentry (QA)"

  @allowed_paths ["/team", "/team/presentation"]
  @allowed_prefixes ["/team/images/"]

  # By name, so this sign-in code does not depend on the team pages (they are
  # in the admin deploy lane, .github/deploy-lanes.txt).
  @allowed_views ~w(TalesForgeWeb.TeamLive TalesForgeWeb.TeamPresentationLive
                    TalesForgeWeb.TeamPrFeedLive TalesForgeWeb.OnlineHeaderLive
                    TalesForgeWeb.TeamChatLive)

  # Events that only change what this browser shows (open or close a card or
  # the chat, sort, filter, cancel a form). Every other event is refused for a
  # read-only session, also events added later.
  @read_events ~w(open close toggle chat validate validate_images cancel_image
                  toggle_sort toggle_tag clear_tags cancel_comment cancel_downvote
                  edit_refinement cancel_refinement draft_change)

  @refused "This QA session is read-only. Gentry (QA) can view the page but cannot change it."

  @doc "The name the QA session shows."
  @spec name() :: String.t()
  def name, do: @name

  @doc "The email the QA session uses inside the app (not a real address)."
  @spec email() :: String.t()
  def email, do: @email

  @doc "The message for a refused write."
  @spec refused_message() :: String.t()
  def refused_message, do: @refused

  @doc "True when GENTRY_QA_TOKEN is set (the QA sign-in is on)."
  @spec enabled?() :: boolean()
  def enabled?, do: not is_nil(configured_token())

  @doc """
  True when `given` is the configured token. Timing safe. A missing or blank
  token, or no configured token, is false.

      iex> TalesForge.QaLogin.token_valid?(nil)
      false
  """
  @spec token_valid?(term()) :: boolean()
  def token_valid?(given) do
    with expected when is_binary(expected) <- configured_token(),
         given when is_binary(given) <- trimmed(given) do
      Plug.Crypto.secure_compare(:crypto.hash(:sha256, given), :crypto.hash(:sha256, expected))
    else
      _ -> false
    end
  end

  @doc "Starts the QA session (call only after `token_valid?/1`)."
  @spec put_session(Plug.Conn.t()) :: Plug.Conn.t()
  def put_session(conn) do
    conn
    |> Plug.Conn.configure_session(renew: true)
    |> Plug.Conn.put_session(@identity_key, @identity)
    |> Plug.Conn.put_session(@tag_key, tag(configured_token()))
  end

  @doc "The session keys of the QA session (for sign-out)."
  @spec session_keys() :: [String.t()]
  def session_keys, do: [@identity_key, @tag_key]

  @doc """
  True when the session is a QA session for the token that is configured now.

      iex> TalesForge.QaLogin.valid_session?(%{})
      false
  """
  @spec valid_session?(Plug.Conn.t() | map() | term()) :: boolean()
  def valid_session?(%Plug.Conn{} = conn), do: valid_session?(Plug.Conn.get_session(conn))

  def valid_session?(%{@identity_key => @identity, @tag_key => given}) when is_binary(given) do
    case configured_token() do
      nil -> false
      token -> Plug.Crypto.secure_compare(given, tag(token))
    end
  end

  def valid_session?(_), do: false

  @doc """
  True for the paths a QA session can open.

      iex> TalesForge.QaLogin.allowed_path?("/team/presentation")
      true
      iex> TalesForge.QaLogin.allowed_path?("/admin")
      false
  """
  @spec allowed_path?(String.t()) :: boolean()
  def allowed_path?(path) when is_binary(path),
    do: path in @allowed_paths or String.starts_with?(path, @allowed_prefixes)

  @doc """
  True for the LiveViews a QA session can mount.

      iex> TalesForge.QaLogin.allowed_view?(TalesForgeWeb.TeamLive)
      true
      iex> TalesForge.QaLogin.allowed_view?(TalesForgeWeb.HomeLive)
      false
  """
  @spec allowed_view?(module()) :: boolean()
  def allowed_view?(view) when is_atom(view), do: inspect(view) in @allowed_views
  def allowed_view?(_view), do: false

  @doc """
  True for an event that only changes what this browser shows.

      iex> TalesForge.QaLogin.read_event?("open")
      true
      iex> TalesForge.QaLogin.read_event?("comment")
      false
  """
  @spec read_event?(String.t()) :: boolean()
  def read_event?(event), do: event in @read_events

  @doc """
  True when the QA session is read-only. Always true on production and
  locally; on playtest false only while QA_ALLOW_WRITES is on.
  """
  @spec read_only?() :: boolean()
  def read_only? do
    not (AppRole.role() == :playtest and config()[:allow_writes] == true)
  end

  defp tag(token),
    do: :crypto.mac(:hmac, :sha256, token, "tales-forge qa session") |> Base.url_encode64()

  defp configured_token, do: trimmed(config()[:token])

  defp config, do: Application.get_env(:ex_tales_forge, :qa_login, [])

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      v -> v
    end
  end

  defp trimmed(_), do: nil
end
