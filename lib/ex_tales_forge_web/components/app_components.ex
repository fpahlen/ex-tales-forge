defmodule TalesForgeWeb.AppComponents do
  @moduledoc """
  Components that show which app you are on and link across the two apps
  (admin split, docs/decisions.md 2026-10-10):

  - `env_badge/1`: a pill with this app's role (PRODUCTION, PLAYTEST or
    LOCAL) and the short commit it runs. On production and playtest it is
    a link to the other app (`switch_url/2`). The admin top bar and the
    play pages' top bar show it.
  - `lives_on/1`: "<what> lives on production ↗", a link to a one-home page
    (`TalesForge.AppRole` area) on the app that owns it.
  - `other_app_link/1`: "Same page on playtest ↗", for pages that exist on
    both apps with different data (sessions, costs, telemetry).

  The role comes from `TalesForge.AppRole.role/1`; tests can pass `role`.
  """

  use Phoenix.Component

  alias TalesForge.AppRole
  alias TalesForge.Playtest.RunMeta

  @doc """
  The environment badge. `role` defaults to this app's role; `sha` to the
  commit it runs (`GIT_SHA`), shown as 7 characters when known.

  On production and playtest the badge is a link to the other app, with a
  ⇄ and the text "You are on production. Switch to playtest." as its
  tooltip and screen-reader text. `switch_path` is the path to open there
  (`switch_url/2`): admin pages give their `other_app_path`, and the play
  pages give the game list. Locally the badge is a label. The link's tap
  area is at least 44px tall.
  """
  attr :id, :string, default: "env-badge"
  attr :role, :atom, default: nil
  attr :sha, :string, default: nil

  attr :switch_path, :string,
    default: nil,
    doc: "the path to open on the other app; nil opens the other app's /admin"

  attr :compact, :boolean,
    default: false,
    doc: "hide the commit on a phone, for a crowded top bar (the tooltip keeps the role)"

  attr :class, :string, default: nil

  @spec env_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def env_badge(assigns) do
    role = assigns.role || AppRole.role()
    short = short_sha(assigns.sha || RunMeta.git_sha())

    assigns =
      assign(assigns,
        role: role,
        short: short,
        name: role_name(role),
        href: switch_url(assigns.switch_path, role),
        title: badge_title(role, AppRole.app_name(), short)
      )

    ~H"""
    <a
      :if={@href}
      id={@id}
      href={@href}
      data-role={@role}
      data-cross-app
      title={@title}
      class={["group inline-flex min-h-11 max-w-full items-center", @class]}
    >
      <.pill role={@role} name={@name} short={@short} compact={@compact} switch />
      <span class="sr-only">{@title}</span>
    </a>
    <span
      :if={!@href}
      id={@id}
      data-role={@role}
      title={@title}
      class={["inline-flex max-w-full items-center", @class]}
    >
      <.pill role={@role} name={@name} short={@short} compact={@compact} />
    </span>
    """
  end

  attr :role, :atom, required: true
  attr :name, :string, required: true
  attr :short, :string, default: nil
  attr :compact, :boolean, default: false
  attr :switch, :boolean, default: false

  defp pill(assigns) do
    ~H"""
    <span class={[
      "inline-flex max-w-full items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-bold tracking-wide",
      role_class(@role),
      @switch &&
        "group-hover:brightness-110 group-focus-visible:ring-2 group-focus-visible:ring-current"
    ]}>
      <span class="size-2 shrink-0 rounded-full bg-current" aria-hidden="true"></span>
      <span>{@name}</span>
      <span
        :if={@short}
        class={["font-mono font-normal opacity-80", @compact && "hidden sm:inline"]}
      >
        {@short}
      </span>
      <span :if={@switch} aria-hidden="true">⇄</span>
    </span>
    """
  end

  @doc """
  The address that the badge opens: `path` on the other app, or the other
  app's /admin when `path` is nil. Nil locally, where there is no other app.

      iex> TalesForgeWeb.AppComponents.switch_url("/admin/operate/costs", :production)
      "https://tales-forge-playtest.fly.dev/admin/operate/costs"
      iex> TalesForgeWeb.AppComponents.switch_url(nil, :playtest)
      "https://tales-forge.fly.dev/admin"
      iex> TalesForgeWeb.AppComponents.switch_url("/", :local)
      nil
  """
  @spec switch_url(String.t() | nil, AppRole.role()) :: String.t() | nil
  def switch_url(path, role), do: other_app_url(path || "/admin", role)

  @doc """
  The badge's tooltip. On production and playtest it names the switch.

      iex> TalesForgeWeb.AppComponents.badge_title(:production, "tales-forge", "abcdef1")
      "You are on production. Switch to playtest."
      iex> TalesForgeWeb.AppComponents.badge_title(:playtest, "tales-forge-playtest", nil)
      "You are on playtest. Switch to production."
      iex> TalesForgeWeb.AppComponents.badge_title(:local, "local", "abcdef1")
      "You are on local (local, commit abcdef1)"
  """
  @spec badge_title(AppRole.role(), String.t(), String.t() | nil) :: String.t()
  def badge_title(role, app, short) do
    case other(role) do
      nil -> "You are on #{role} (#{app}#{short && ", commit " <> short})"
      other -> "You are on #{role}. Switch to #{other}."
    end
  end

  defp short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)
  defp short_sha(_sha), do: nil

  @doc """
  A link to a page that lives on one app only. Shows nothing when that page
  lives here. Example: "The idea board lives on production ↗".
  """
  attr :id, :string, default: nil
  attr :area, :atom, required: true
  attr :path, :string, required: true
  attr :what, :string, required: true
  attr :role, :atom, default: nil

  @spec lives_on(map()) :: Phoenix.LiveView.Rendered.t()
  def lives_on(assigns) do
    role = assigns.role || AppRole.role()

    assigns =
      assign(assigns,
        here?: AppRole.here?(assigns.area, role),
        href: AppRole.link(assigns.area, assigns.path, role),
        home: AppRole.home_label(assigns.area)
      )

    ~H"""
    <a
      :if={not @here?}
      id={@id}
      href={@href}
      data-cross-app
      class="inline-flex min-h-11 items-center gap-1 font-semibold text-[var(--paper-accent)] underline"
    >
      {@what} lives on {@home} ↗
    </a>
    """
  end

  @doc """
  "Same page on <other app> ↗" for a page that both apps serve with their own
  data. `path` is the page's path (with its query, if any). Shows nothing
  locally, where there is no other app.
  """
  attr :id, :string, default: "other-app-link"
  attr :path, :string, required: true
  attr :role, :atom, default: nil

  @spec other_app_link(map()) :: Phoenix.LiveView.Rendered.t()
  def other_app_link(assigns) do
    role = assigns.role || AppRole.role()
    assigns = assign(assigns, :other, other(role))

    ~H"""
    <a
      :if={@other}
      id={@id}
      href={other_url(@other, @path)}
      data-cross-app
      class="inline-flex min-h-11 items-center gap-1 text-sm font-semibold text-[var(--paper-accent)] underline"
    >
      Same page on {@other} ↗
    </a>
    """
  end

  @doc """
  The full URL of `path` on the other app, or nil locally.

      iex> TalesForgeWeb.AppComponents.other_app_url("/admin/operate/costs", :production)
      "https://tales-forge-playtest.fly.dev/admin/operate/costs"
      iex> TalesForgeWeb.AppComponents.other_app_url("/admin/play/sessions", :playtest)
      "https://tales-forge.fly.dev/admin/play/sessions"
      iex> TalesForgeWeb.AppComponents.other_app_url("/admin", :local)
      nil
  """
  @spec other_app_url(String.t(), AppRole.role()) :: String.t() | nil
  def other_app_url(path, role \\ AppRole.role()), do: role |> other() |> other_url(path)

  @doc """
  The display name of a role.

      iex> TalesForgeWeb.AppComponents.role_name(:playtest)
      "PLAYTEST"
  """
  @spec role_name(AppRole.role()) :: String.t()
  def role_name(:production), do: "PRODUCTION"
  def role_name(:playtest), do: "PLAYTEST"
  def role_name(_local), do: "LOCAL"

  defp role_class(:production), do: "border-red-800 bg-red-700 text-white"
  defp role_class(:playtest), do: "border-amber-700 bg-amber-300 text-amber-950"
  defp role_class(_local), do: "border-slate-500 bg-slate-200 text-slate-900"

  defp other(:production), do: :playtest
  defp other(:playtest), do: :production
  defp other(_local), do: nil

  defp other_url(nil, _path), do: nil
  defp other_url(app, path), do: String.trim_trailing(AppRole.base_url(app), "/") <> path
end
