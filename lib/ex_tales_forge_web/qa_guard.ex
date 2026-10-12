defmodule TalesForgeWeb.QaGuard do
  @moduledoc """
  The server-side read-only guard for the QA session (the Gentry (QA) sign-in).

  `TalesForgeWeb.QaGuard.attach/1` adds a `:handle_event` hook to a LiveView: for a read-only
  session, every event that is not a read event (`TalesForge.QaLogin.read_event?/1`)
  is stopped before the LiveView sees it. LiveComponents (the idea board) use
  `TalesForgeWeb.QaGuard.refuse?/2` at the top of their `handle_event/3`.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  alias TalesForge.QaLogin

  @doc """
  The `on_mount` result for a session without a GitHub sign-in: a valid QA
  session on an allowed LiveView continues as "Gentry (QA)" (assigns
  `:admin_email`, `:admin_github_login` nil, `:qa` true, `:read_only`, and the
  read-only hook); anything else halts with a redirect to the login page. Not
  tracked in "Online now".
  """
  @spec mount(map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  # The live_session hook and LiveAuth both run on a /team mount: the second
  # call keeps what the first one set up.
  def mount(_session, %{assigns: %{qa: true}} = socket), do: {:cont, socket}

  def mount(session, socket) do
    if QaLogin.valid_session?(session) and QaLogin.allowed_view?(socket.view) do
      {:cont,
       socket
       |> assign(:admin_email, QaLogin.email())
       |> assign(:admin_github_login, nil)
       |> assign(:qa, true)
       |> assign(:read_only, QaLogin.read_only?())
       |> attach()}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/admin/login")}
    end
  end

  @doc "Adds the read-only hook when the socket is a read-only QA session."
  @spec attach(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def attach(%{assigns: %{read_only: true}} = socket) do
    attach_hook(socket, :qa_read_only, :handle_event, fn event, _params, socket ->
      if QaLogin.read_event?(event),
        do: {:cont, socket},
        else: {:halt, put_flash(socket, :error, QaLogin.refused_message())}
    end)
  end

  def attach(socket), do: socket

  @doc "True when `event` must be refused for this socket (read-only and not a read event)."
  @spec refuse?(String.t(), Phoenix.LiveView.Socket.t() | map()) :: boolean()
  def refuse?(event, %{assigns: assigns}), do: refuse?(event, assigns)
  def refuse?(event, %{read_only: true}), do: not QaLogin.read_event?(event)
  def refuse?(_event, _assigns), do: false

  @doc "Shows the refusal in a LiveComponent's form error."
  @spec refused(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def refused(socket), do: assign(socket, :form_error, QaLogin.refused_message())
end
