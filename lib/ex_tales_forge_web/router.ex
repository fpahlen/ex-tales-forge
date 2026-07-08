defmodule TalesForgeWeb.Router do
  use TalesForgeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TalesForgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TalesForgeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TalesForgeWeb.Plugs.AdminAuth
  end

  scope "/admin", TalesForgeWeb.AdminLive do
    pipe_through :admin

    live "/", DashboardLive, :index
    live "/sessions", SessionLive.Index, :index
    live "/sessions/:id", SessionLive.Show, :show
    live "/sessions/:id/npcs", NpcLive.Index, :index
    live "/sessions/:id/npcs/:npc_id", NpcLive.Show, :show
    live "/sessions/:id/turns", TurnLive.Index, :index
    live "/npc-definitions", NpcDefinitionLive.Index, :index
    live "/npc-definitions/:id", NpcDefinitionLive.Show, :show
  end

  scope "/admin" do
    pipe_through :admin

    import Phoenix.LiveDashboard.Router

    live_dashboard "/oban", metrics: TalesForgeWeb.Telemetry
  end

  scope "/", TalesForgeWeb do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/play/:id", PlayLive, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", TalesForgeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ex_tales_forge, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TalesForgeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
