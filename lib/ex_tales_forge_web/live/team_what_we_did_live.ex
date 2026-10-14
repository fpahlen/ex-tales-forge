defmodule TalesForgeWeb.TeamWhatWeDidLive do
  @moduledoc """
  The "What have we done" panel on `/team`, nested in `TalesForgeWeb.TeamLive`
  with `live_render/3`.

  On mount it shows the cached panel, else the plain titles
  (`TalesForge.PrFeed.WhatWeDid.cached_or_titles/3`); this never calls the
  model. Once connected it makes the panel in a task
  (`TalesForge.PrFeed.WhatWeDid.summary/3`, one cached model call) and again
  on each `{:pr_feed, snapshot}`. No events.
  """

  use TalesForgeWeb, :live_view

  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.WhatWeDid
  alias TalesForgeWeb.TeamWhatWeDid

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    merged = merged(PrFeed.snapshot())
    socket = assign(socket, summary: WhatWeDid.cached_or_titles(merged, DateTime.utc_now()))

    if connected?(socket) do
      PrFeed.subscribe()
      {:ok, refresh(socket, merged)}
    else
      {:ok, assign(socket, loading: false)}
    end
  end

  @impl true
  def handle_info({:pr_feed, snapshot}, socket), do: {:noreply, refresh(socket, merged(snapshot))}

  @impl true
  def handle_async(:summary, {:ok, summary}, socket),
    do: {:noreply, assign(socket, summary: summary, loading: false)}

  def handle_async(:summary, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, loading: false)}

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <TeamWhatWeDid.panel summary={@summary} loading={@loading} />
    """
  end

  defp refresh(socket, merged) do
    now = DateTime.utc_now()
    loading = socket.assigns.summary.source == :titles and socket.assigns.summary.count > 0

    socket
    |> assign(loading: loading)
    |> start_async(:summary, fn -> WhatWeDid.summary(merged, now) end)
  end

  defp merged(snapshot), do: Map.get(snapshot, :merged, [])
end
