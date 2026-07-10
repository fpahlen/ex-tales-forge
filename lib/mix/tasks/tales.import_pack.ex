defmodule Mix.Tasks.Tales.ImportPack do
  @moduledoc """
  Import a game pack (directory of linked Markdown files) into the Ash authoring layer.

  The pack is processed with interactive confirmations (per the design for explicit imports).

      mix tales.import_pack priv/adventures/generic-demo
      mix tales.import_pack "path/to/Drakar och Demoner"
      mix tales.import_pack priv/adventures/crossroads_ledger --dry-run
      mix tales.import_pack /path/to/pack --yes   # auto-accept all (non-interactive)

  The top-level folder name of the pack becomes the adventure_id (or use frontmatter).

  After a successful import you can create a session with:

      mix run -e 'TalesForge.GameSessions.create_session(%{adventure_id: "your-pack-id"})'
  """

  use Mix.Task

  @shortdoc "Import a linked-markdown game pack with interactive confirmations"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          dry_run: :boolean,
          yes: :boolean,
          force: :boolean,
          "adventure-id": :string
        ],
        aliases: [y: :yes, d: :dry_run]
      )

    pack_dir =
      case positional do
        [path | _] -> Path.expand(path)
        _ -> Mix.raise("Usage: mix tales.import_pack path/to/pack [options]")
      end

    unless File.dir?(pack_dir) do
      Mix.raise("Pack directory not found: #{pack_dir}")
    end

    dry_run? = Keyword.get(opts, :dry_run, false)
    auto_accept? = Keyword.get(opts, :yes, false) or Keyword.get(opts, :force, false)
    adventure_id_override = Keyword.get(opts, :"adventure-id")

    Mix.shell().info("Importing pack: #{pack_dir}")
    if dry_run?, do: Mix.shell().info("  (dry-run mode - no changes will be written)")
    if auto_accept?, do: Mix.shell().info("  (auto-accept mode)")

    confirmer =
      if auto_accept? do
        &auto_accept_confirmer/1
      else
        &cli_confirmer/1
      end

    import_opts =
      [
        confirmer: confirmer,
        dry_run: dry_run?
      ]
      |> then(fn o ->
        if adventure_id_override,
          do: Keyword.put(o, :adventure_id, adventure_id_override),
          else: o
      end)

    case TalesForge.Authoring.Importer.import_pack(pack_dir, import_opts) do
      {:ok, result} ->
        if dry_run? do
          # Dry run result is %{dry_run: true, pack: pack_data}
          pack = Map.get(result, :pack, result)
          adv_id = Map.get(pack, :adventure_id, "unknown")
          locs = length(Map.get(pack, :locations, []))
          chars = length(Map.get(pack, :npcs, []))
          rules = Map.get(pack, :rules_count, map_size(Map.get(pack, :rules, %{})))

          Mix.shell().info("\n[DRY RUN] Import would succeed.")
          Mix.shell().info("  Adventure: #{adv_id}")
          Mix.shell().info("  Locations: #{locs}")
          Mix.shell().info("  Characters/NPCs: #{chars}")
          Mix.shell().info("  Rules files: #{rules}")
        else
          # Non-dry result from maybe_write_to_ash
          adv = Map.get(result, :adventure, %{})
          adv_id = Map.get(adv, :adventure_id, "unknown")
          loc_count = Map.get(result, :locations, 0)
          npc_count = Map.get(result, :npcs, 0)
          rule_files = Map.get(result, :rules_files, [])

          Mix.shell().info("\n✓ Pack imported successfully!")
          Mix.shell().info("  Adventure: #{adv_id}")
          Mix.shell().info("  Locations imported: #{loc_count}")
          Mix.shell().info("  Characters/NPCs imported: #{npc_count}")
          Mix.shell().info("  Rules files: #{length(rule_files)}")

          Mix.shell().info("\nYou can now create a session with this adventure:")

          suggestion = """
            mix run -e '
              {:ok, s} = TalesForge.GameSessions.create_session(%{adventure_id: "#{adv_id}"})
              IO.puts("Session: \#{s.id}")
            '
          """

          Mix.shell().info(suggestion)
        end

      {:error, :import_cancelled_by_user} ->
        Mix.shell().info("\nImport cancelled by user.")

      {:error, reason} ->
        Mix.shell().error("\nImport failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  # --- Confirmers ---

  defp cli_confirmer(proposal) do
    Mix.shell().info("")

    question = proposal.question
    source = Map.get(proposal, :source_file)

    Mix.shell().info(question)
    if source, do: Mix.shell().info("  source: #{source}")

    if proposal.type == :final do
      Mix.shell().info("")

      Mix.shell().info(
        "This is the final confirmation. Once accepted, the pack will be written to the database."
      )
    end

    prompt = if proposal.type == :final, do: "  Confirm? [Y/n] ", else: "  Proceed? [Y/n] "

    answer =
      Mix.shell().prompt(prompt)
      |> String.trim()
      |> String.downcase()

    case answer do
      "y" ->
        true

      "yes" ->
        true

      "n" ->
        false

      "no" ->
        false

      # default to yes
      "" ->
        true

      _ ->
        Mix.shell().info("  Unrecognized answer. Treating as no.")
        false
    end
  end

  defp auto_accept_confirmer(_proposal), do: true
end
