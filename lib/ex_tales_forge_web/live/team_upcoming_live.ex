defmodule TalesForgeWeb.TeamUpcomingLive do
  @moduledoc """
  The Upcoming panel on `/team` (`TalesForgeWeb.TeamUpcoming`), nested in
  `TalesForgeWeb.TeamLive` with `live_render/3`, so its updates patch only
  this part of the page.

  Once connected it subscribes to the run changes
  (`TalesForge.Board.Schedule.topic/0`) and renders the rows again on each
  change and every minute (the next times move on). Sign-in as for every
  LiveView (`TalesForgeWeb.LiveAuth`).
  """

  use TalesForgeWeb, :live_view

  alias TalesForge.Board.Schedule
  alias TalesForgeWeb.TeamUpcoming

  @tick_ms 60_000

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Schedule.subscribe()
      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok, assign_rows(socket)}
  end

  @impl true
  def handle_info({:schedule, :changed}, socket), do: {:noreply, assign_rows(socket)}
  def handle_info(:tick, socket), do: {:noreply, assign_rows(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp assign_rows(socket),
    do: assign(socket, :rows, TeamUpcoming.rows(Workflow.Team.Source.team(), DateTime.utc_now()))

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <TeamUpcoming.panel rows={@rows} />
    """
  end
end
