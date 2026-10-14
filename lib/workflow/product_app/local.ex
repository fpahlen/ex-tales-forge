defmodule Workflow.ProductApp.Local do
  @moduledoc """
  The local adapter of `Workflow.ProductApp`. It calls the product-app API
  module (`TalesForge.ProductApi`) in the same release. This is the only
  Workflow file that calls the product app directly
  (`priv/team/data-boundary.txt`, `[adapter]`). A later card replaces it with
  `Workflow.ProductApp.Http`.
  """

  @behaviour Workflow.ProductApp

  alias TalesForge.ProductApi

  @impl Workflow.ProductApp
  def costs(now), do: {:ok, ProductApi.costs(now)}

  @impl Workflow.ProductApp
  def online, do: {:ok, ProductApi.online()}

  @impl Workflow.ProductApp
  def running_commits, do: {:ok, ProductApi.running_commits()}

  @impl Workflow.ProductApp
  def persona_scores, do: {:ok, ProductApi.persona_scores()}
end
