defmodule TalesForge.PubSub.GameSession do
  @moduledoc """
  Phoenix PubSub bridge for live game session updates.
  """

  @pubsub TalesForge.PubSub

  def topic(session_id), do: "game_session:#{session_id}"

  def subscribe(session_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(session_id))
  end

  def broadcast(session_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(session_id), event)
  end
end
