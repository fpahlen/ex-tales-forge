defmodule TalesForgeWeb.TeamDetailsLive do
  @moduledoc """
  The founders' details page at `/team/details`: the long text behind each
  slide of `/team/presentation` (`TalesForgeWeb.TeamPresentationLive`), one
  section for each slide, with the same anchors as the slides (`#team`,
  `#board`, `#rules`, ...). The slides keep the short text and one widget
  each; a link on each slide opens its section here.

  Behind the GitHub team sign-in like `/team` (the `:team` live session).
  Read-only: no events. It uses the same numbers as the presentation
  (`TalesForge.TeamPace`, `TalesForgeWeb.TeamLiveNumbers`, `TalesForge.TeamPage`),
  and the board counts where the board is (`TalesForge.AppRole.here?(:board)`).
  """

  use TalesForgeWeb, :live_view

  alias TalesForge.AppRole
  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.Extras
  alias TalesForge.TeamPace
  alias TalesForge.TeamPage
  alias TalesForgeWeb.Layouts
  alias TalesForgeWeb.TeamLayout
  alias TalesForgeWeb.TeamLiveNumbers
  alias TalesForgeWeb.TeamPresentationLive

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket), do: PrFeed.subscribe()
    d = TeamPage.data()

    {:ok,
     socket
     |> assign(:page_title, "Team · details")
     |> assign(:d, d)
     |> assign(:pace, TeamPace.current(PrFeed.snapshot(), d))
     |> assign(:live, TeamLiveNumbers.all(d, Extras.current()))
     |> assign(:board_live, if(AppRole.here?(:board), do: TalesForge.Board.stats()))}
  end

  @impl true
  def handle_info({:pr_feed, snapshot}, socket) do
    d = socket.assigns.d

    {:noreply,
     socket
     |> assign(:pace, TeamPace.current(snapshot, d))
     |> assign(:live, TeamLiveNumbers.all(d, Extras.current()))}
  end

  def handle_info(_other, socket), do: {:noreply, socket}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div
      id="team-page"
      class="team-page paper-themed paper-home min-h-dvh"
      phx-hook="TeamPage"
      data-motion="auto"
    >
      <a
        id="skip-to-content"
        href="#team-main"
        class="sr-only focus:not-sr-only focus:fixed focus:left-2 focus:top-2 focus:z-50 focus:rounded focus:bg-[var(--paper-panel)] focus:px-3 focus:py-2 focus:text-[var(--paper-ink)] focus:ring-2"
      >
        Skip to content
      </a>
      <TeamLayout.header
        socket={assigns[:socket]}
        page={:details}
        items={TeamPresentationLive.details_sections()}
      />
      <main
        id="team-main"
        tabindex="-1"
        class="mx-auto max-w-6xl space-y-20 px-4 pb-16 pt-8 sm:px-6 sm:pt-12"
      >
        <header class="space-y-2">
          <h1 class="font-serif text-4xl font-bold">The details behind the presentation</h1>
          <p class="text-[var(--paper-muted)]">
            One section for each slide.
            <.link navigate={~p"/team/presentation"} class="underline">Back to the presentation →</.link>
          </p>
        </header>
        <TeamPresentationLive.details d={@d} pace={@pace} live={@live} board_live={@board_live} />
      </main>
      <TeamLayout.footer d={@d} />
      <Layouts.flash_group flash={@flash} />
    </div>
    """
  end
end
