defmodule TalesForgeWeb.TeamTime do
  @moduledoc """
  Relative times on card comments and in the team chat: "just now",
  "2 min ago", "3 h ago", "yesterday", "4 days ago", then the date (Stockholm)
  from 7 days. The full Stockholm time (with CET or CEST) is in the `title`, so
  it shows on hover.

  The server renders the text (the fallback without JavaScript). The
  `startRelativeTimes` helper in assets/js/team_hooks.js (started by the
  TeamPage and TeamChat hooks) writes the text again every minute with the
  same rules, from the `datetime` attribute. There is no server tick.
  """
  use Phoenix.Component

  alias TalesForgeWeb.TimeAgo

  @zone "Europe/Stockholm"

  @doc """
  The words for `then`, seen at `now`.

  ## Examples

      iex> now = ~U[2026-10-12 10:00:00Z]
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-12 09:59:30Z], now)
      "just now"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-12 09:58:00Z], now)
      "2 min ago"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-12 09:00:01Z], now)
      "59 min ago"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-12 07:00:00Z], now)
      "3 h ago"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-11 09:00:00Z], now)
      "yesterday"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-08 10:00:00Z], now)
      "4 days ago"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-05 10:00:00Z], now)
      "5 Oct"
      iex> TalesForgeWeb.TeamTime.relative(~U[2025-12-31 23:30:00Z], now)
      "1 Jan"
      iex> TalesForgeWeb.TeamTime.relative(~U[2025-10-01 10:00:00Z], now)
      "1 Oct 2025"
      iex> TalesForgeWeb.TeamTime.relative(~U[2026-10-12 10:00:20Z], now)
      "just now"
  """
  @spec relative(DateTime.t(), DateTime.t()) :: String.t()
  def relative(%DateTime{} = then, %DateTime{} = now \\ DateTime.utc_now()) do
    s = max(DateTime.diff(now, then, :second), 0)

    cond do
      s < 60 -> "just now"
      s < 3600 -> "#{div(s, 60)} min ago"
      s < 86_400 -> "#{div(s, 3600)} h ago"
      s < 2 * 86_400 -> "yesterday"
      s < 7 * 86_400 -> "#{div(s, 86_400)} days ago"
      true -> date(then, now)
    end
  end

  defp date(then, now) do
    local = DateTime.shift_zone!(then, @zone, TimeZoneInfo.TimeZoneDatabase)
    this_year = DateTime.shift_zone!(now, @zone, TimeZoneInfo.TimeZoneDatabase).year
    format = if local.year == this_year, do: "%-d %b", else: "%-d %b %Y"
    Calendar.strftime(local, format)
  end

  @doc "A `<time>` with the relative text, the ISO time and the Stockholm time on hover."
  attr :at, DateTime, required: true
  attr :now, DateTime, default: nil, doc: "for tests; defaults to the render time"
  attr :class, :any, default: nil
  attr :rest, :global

  def ago(assigns) do
    assigns = assign(assigns, :now, assigns.now || DateTime.utc_now())

    ~H"""
    <time
      datetime={DateTime.to_iso8601(@at)}
      title={TimeAgo.stockholm(@at)}
      data-team-ago
      class={@class}
      {@rest}
    >{relative(@at, @now)}</time>
    """
  end
end
