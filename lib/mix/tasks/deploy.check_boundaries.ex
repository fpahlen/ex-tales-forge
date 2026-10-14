defmodule Mix.Tasks.Deploy.CheckBoundaries do
  @moduledoc """
  Fails when game or shared code depends on admin code (tales-forge-docs
  `docs/decisions.md`, 2026-10-09, "A fast deploy lane for admin work").

      mix deploy.check_boundaries
      mix deploy.check_boundaries --lanes .github/deploy-lanes.txt

  Admin-only merges deploy to production without Gentry or the playtest batch,
  so an `[admin]` file in `.github/deploy-lanes.txt` must not be something the
  game runs. The task compiles the project, reads the file-level dependency
  graph from `mix xref graph` (compile, export and runtime references) and
  lists every edge from a non-admin file to an `[admin]` file. `[game]` files may
  never have one; other shared files only when they are on `[wiring]` (the
  router and the application mount admin modules).

  It also fails when a pattern on `[admin]` or `[game]` matches no file in the
  repo, so the list doesn't keep stale entries that a renamed file slips past.

  It also checks the data boundary between Workflow and the product app
  (`TalesForge.DeployLanes.DataBoundary`, `priv/team/data-boundary.txt`):
  product-app code does not call `TalesForge.Workflow.Repo` or a Workflow
  schema, and Workflow code does not call `TalesForge.Repo` or a product-app
  schema. CI runs it in the Test job.
  """

  use Mix.Task

  alias TalesForge.DeployLanes
  alias TalesForge.DeployLanes.DataBoundary

  @workflow_files "priv/team/workflow-files.txt"
  @workflow_data ~w(lib/ex_tales_forge/workflow/repo.ex lib/ex_tales_forge/workflow/jobs.ex)
  @product_data ~w(lib/ex_tales_forge/repo.ex)

  @shortdoc "Checks that game and shared code never depend on admin code"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [lanes: :string])
    lanes_path = opts[:lanes] || DeployLanes.default_path()
    lanes = DeployLanes.load(lanes_path)

    Mix.Task.run("compile")
    edges = xref_edges()

    stale = stale_patterns(lanes)
    violations = DeployLanes.boundary_violations(lanes, edges)
    data_violations = DataBoundary.violations(data_sets(), edges)

    case {violations, stale, data_violations} do
      {[], [], []} ->
        Mix.shell().info(
          "deploy.check_boundaries: no game or shared file depends on an [admin] file, " <>
            "and Workflow and the product app keep to their own data " <>
            "(#{length(edges)} dependencies checked)"
        )

      {[], [], data} ->
        Mix.raise(data_failure_message(data))

      _ ->
        Mix.raise(
          failure_message(lanes_path, violations, stale) <>
            if(data_violations == [], do: "", else: "\n" <> data_failure_message(data_violations))
        )
    end
  end

  # The concrete file sets of the data boundary. The schema files come from
  # the compiled modules: a schema with the prefix "workflow" is Workflow data.
  defp data_sets do
    boundary = DataBoundary.default_path() |> File.read!() |> DataBoundary.parse()
    {workflow_schemas, product_schemas} = DataBoundary.split_schemas(schema_files())

    %{
      workflow: expand(read_globs(@workflow_files) ++ boundary.workflow),
      wiring: expand(boundary.wiring),
      pending: expand(boundary.pending),
      workflow_data: MapSet.union(workflow_schemas, MapSet.new(@workflow_data)),
      product_data: MapSet.union(product_schemas, MapSet.new(@product_data))
    }
  end

  defp read_globs(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end

  defp expand(globs), do: globs |> Enum.flat_map(&Path.wildcard/1) |> MapSet.new()

  defp schema_files do
    {:ok, modules} = :application.get_key(:ex_tales_forge, :modules)

    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__schema__, 1),
        module.__schema__(:source) != nil do
      source = module.module_info(:compile)[:source] |> to_string() |> Path.relative_to_cwd()
      {source, module.__schema__(:prefix)}
    end
  end

  @doc false
  @spec data_failure_message([DataBoundary.violation()]) :: String.t()
  def data_failure_message(violations) do
    lines =
      for %{kind: kind, from: from, to: to} <- violations do
        case kind do
          :product_to_workflow -> "  #{from} -> #{to}  (product-app code uses Workflow data)"
          :workflow_to_product -> "  #{from} -> #{to}  (Workflow code uses product-app data)"
        end
      end

    Enum.join(
      [
        "deploy.check_boundaries failed (#{DataBoundary.default_path()}).",
        "Workflow and the product app keep to their own data:"
        | lines
      ] ++
        [
          "Call the context of the other side, or move the file to the correct side. " <>
            "Workflow uses TalesForge.Workflow.Repo; the product app uses TalesForge.Repo."
        ],
      "\n"
    )
  end

  defp xref_edges do
    path =
      Path.join(System.tmp_dir!(), "deploy_lanes_xref_#{System.unique_integer([:positive])}.dot")

    shell = Mix.shell()

    try do
      # Quiet: xref would print how to render the graph as a PNG.
      Mix.shell(Mix.Shell.Quiet)
      Mix.Task.rerun("xref", ["graph", "--format", "dot", "--output", path])
      path |> File.read!() |> DeployLanes.parse_xref_dot()
    after
      Mix.shell(shell)
      File.rm(path)
    end
  end

  defp stale_patterns(lanes) do
    {out, 0} = System.cmd("git", ["ls-files"])
    files = String.split(out, "\n", trim: true)

    for key <- [:admin, :game, :wiring],
        source <- DeployLanes.unused_patterns(lanes, key, files) do
      "[#{key}] #{source}"
    end
  end

  @doc false
  @spec failure_message(String.t(), [map()], [String.t()]) :: String.t()
  def failure_message(lanes_path, violations, stale) do
    edges =
      for %{kind: kind, from: from, to: to} <- violations do
        "  #{from} -> #{to}  (#{kind} code depends on admin code)"
      end

    stale_lines = for line <- stale, do: "  #{line} matches no file in the repo"

    [
      "deploy.check_boundaries failed (#{lanes_path}).",
      if(edges == [],
        do: nil,
        else:
          "Admin-only merges deploy to production without Gentry or the playtest batch, so game and " <>
            "shared code must not depend on [admin] files:"
      ),
      edges,
      if(edges == [],
        do: nil,
        else:
          "Move the shared part out of the admin file into a non-admin module, or (for a router or " <>
            "supervisor that only mounts it) add the dependent file to [wiring]."
      ),
      if(stale_lines == [], do: nil, else: "Stale patterns (fix or remove them):"),
      stale_lines
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end
end
