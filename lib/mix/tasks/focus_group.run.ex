defmodule Mix.Tasks.FocusGroup.Run do
  @moduledoc """
  Runs the persona focus group after a playtest batch and writes the report.
  Needs `FOCUS_GROUP_ENABLED=true` (plus `LLM_PROVIDER` and a key for a live
  run). The default is off.

      FOCUS_GROUP_ENABLED=true mix focus_group.run
      FOCUS_GROUP_ENABLED=true mix focus_group.run --personas hawk,ronny
      mix focus_group.run --dry-run
      FOCUS_GROUP_ENABLED=true mix focus_group.run --out docs/research/focus-group-batch-7.md

  `--dry-run` prints the prompts and the brief size for each persona and makes
  no AI call. It also works with the flag off.

  The task prints the short digest for the idea board card at the end. On a
  release, call `TalesForge.Playtest.FocusGroup.run/1` over rpc instead.
  """
  use Mix.Task

  alias TalesForge.Playtest.{FocusGroup, Personas}
  alias TalesForge.Playtest.FocusGroup.{Brief, Report}

  @shortdoc "Interview the playtest personas about the game"

  @impl Mix.Task
  def run(args) do
    {opts, _positional, _} =
      OptionParser.parse(args, strict: [personas: :string, out: :string, dry_run: :boolean])

    ids =
      case opts[:personas] do
        nil -> FocusGroup.persona_ids()
        list -> list |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    Mix.Task.run("app.start")

    if opts[:dry_run], do: dry_run(ids), else: live(ids, opts)
  end

  defp dry_run(ids) do
    for id <- ids do
      {:ok, persona} = Personas.fetch(id)
      p = FocusGroup.prompts(persona)

      Mix.shell().info(
        "== #{persona.name}: brief #{Brief.tokens(p.brief)} tokens (cap #{Brief.max_tokens()})\n#{p.user}"
      )
    end
  end

  defp live(ids, opts) do
    case FocusGroup.run(personas: ids) do
      {:error, :disabled} ->
        Mix.raise("The focus group is off. Set FOCUS_GROUP_ENABLED=true to run it.")

      {:ok, interviews, failures} ->
        path = opts[:out] || Report.default_path()
        File.mkdir_p!(Path.dirname(path))

        File.write!(
          path,
          Report.markdown(interviews, failures, model: TalesForge.LLM.tier2_model())
        )

        Mix.shell().info("Report written to #{path}")
        Mix.shell().info(Report.digest(interviews, failures, path))
    end
  end
end
