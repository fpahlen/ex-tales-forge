defmodule Mix.Tasks.Workflow.CheckNames do
  @moduledoc """
  Fails when a Workflow `lib/` file has a team name (board card "Workflow
  split 2/5: Team config").

      mix workflow.check_names

  The task reads the globs in `priv/team/workflow-files.txt` and the team
  config (`Workflow.Team.Source`). Then it gives the files to
  `Workflow.NameCheck`. It reads only the Workflow `lib/` files, so a name in
  a test or in a game file is not a finding. CI runs it in the Test job.
  """

  use Mix.Task

  @shortdoc "Checks that Workflow lib/ files have no team names"
  @list "priv/team/workflow-files.txt"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_args) do
    Mix.Task.run("compile")

    files =
      @list
      |> File.read!()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.filter(&String.starts_with?(&1, "lib/"))
      |> Enum.uniq()
      |> Enum.map(&{&1, File.read!(&1)})

    case Workflow.NameCheck.findings(Workflow.Team.Source.team(), files) do
      [] ->
        Mix.shell().info(
          "workflow.check_names: #{length(files)} Workflow files have no team names"
        )

      found ->
        lines = Enum.map(found, &"  #{&1.path}:#{&1.line}: #{&1.name}: #{&1.text}")

        Mix.raise(
          "workflow.check_names: #{length(found)} team names in Workflow lib/ files. " <>
            "Move them to the team config (Workflow.Team):\n" <> Enum.join(lines, "\n")
        )
    end
  end
end
