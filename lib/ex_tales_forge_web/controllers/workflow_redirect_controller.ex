defmodule TalesForgeWeb.WorkflowRedirectController do
  @moduledoc """
  Workflow moved to its own app (whyse-workflow, board card "Workflow split
  5/5"). For 30 days, the old Workflow URLs on the product app
  (`TalesForge.AppRole.workflow_paths/0`) redirect to the same path and query
  on Workflow (`TalesForge.AppRole.base_url(:workflow)`).

  The status is 307, so a POST stays a POST. Workflow does its own sign-in and
  token checks. Remove the routes after the 30 days.
  """

  use TalesForgeWeb, :controller

  alias TalesForge.AppRole

  @doc "Redirects the request to the same path and query on Workflow."
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    conn
    |> put_status(307)
    |> redirect(external: workflow_url(conn.request_path, conn.query_string))
  end

  @doc """
  The Workflow URL of `path` with `query`.

      iex> TalesForgeWeb.WorkflowRedirectController.workflow_url("/team", "x=1")
      "https://whyse-workflow.fly.dev/team?x=1"
      iex> TalesForgeWeb.WorkflowRedirectController.workflow_url("/internal/board/ideas", "")
      "https://whyse-workflow.fly.dev/internal/board/ideas"
  """
  @spec workflow_url(String.t(), String.t() | nil) :: String.t()
  def workflow_url(path, query) do
    base = AppRole.base_url(:workflow) |> String.trim_trailing("/")
    if query in [nil, ""], do: base <> path, else: base <> path <> "?" <> query
  end
end
