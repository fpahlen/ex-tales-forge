defmodule TalesForge.Repo.Migrations.BoardGoals do
  @moduledoc """
  Goals on the founders' idea board (tales-forge-docs `docs/design-idea-board.md`,
  "Goals"). Add only: a goals table, one vote per founder per goal (a -1 has a
  reason), a nullable `goal_id` on each card, then the seed.

  The seed is idempotent. It adds the six goals of `docs/roadmap-2027.md`
  (G2 to G7) by `key` (ON CONFLICT DO NOTHING) and sets the goal of the cards
  in the goals draft (2026-10-12). A card matches by id, else by its exact
  title. A card that has a goal already keeps it.
  """
  use Ecto.Migration

  @goals [
    {"G2", "Playable game on the Elixir rewrite",
     "The core loop is at parity with the old app, p95 response is 3 s or less in self-play, a free first session in Tin Valley is playable, and the go/no-go on the rewrite is made.",
     "2026-12-31", "Dec 2026, go/no-go", 2},
    {"G3", "Bot loop runs safely",
     "Bots build 24/7 on staging, five persona agents score every build with latency and cost per session, and a monthly AI spend cap with an 80 % alert and a hard stop is set.",
     "2026-11-30", "Nov 2026", 3},
    {"G4", "We can take money",
     "A free first offer and a first paid offer are defined, and live payments with prepaid credits work through a legal seller with terms and VAT.",
     "2027-03-31", "Mar 2027", 4},
    {"G5", "Closed beta and growth",
     "A closed beta recruited from RPG forums runs, the v1 growth features ship, and the public launch is made.",
     "2027-06-30", "Jun 2027", 5},
    {"G6", "Old app retired",
     "Existing users are migrated, DNS is cut over, and the old app is shut down after the final export.",
     "2027-05-31", "May 2027", 6},
    {"G7", "Our shared workspace (team tools)",
     "The founders' team tools (the board, the team page, the chat and the presentation) do the work that the founders need.",
     "2026-10-31", "31 Oct 2026", 7}
  ]

  # {card id on production, card title, goal key} from /workspace/goals/draft.md.
  # The 16 cards that the draft has as Unassigned (team tools) go to G7.
  @cards [
    {"4efe811f-e7b9-4cad-a13f-f41d8c2b7b64", "The Tin Valley starter scope", "G2"},
    {"938c331b-ea5a-45eb-afbd-ea8eb0121355", "Worlds", "G2"},
    {"0ab31ff4-c605-4aa2-8a65-e067dc23649c", "Have Case explain a technical detail", "G7"},
    {"7a7c5f6d-50f0-4d5f-89c5-3a0a63400101",
     "Set release thresholds for persona scores, cost per session and latency", "G3"},
    {"1b3a88de-fc22-4259-8454-91b418ba985e",
     "Choose a coding-bot platform and set the guardrails", "G3"},
    {"310dd4ef-284a-4769-9a8c-775e76bd6961", "The free first experience and the first paid offer",
     "G4"},
    {"e08fff73-1059-4ca6-ba94-d4200e1a3df6", "The payment provider and credit design", "G4"},
    {"ea42a6bf-9e21-4a3d-8513-72d901576e49", "Company, terms and tax for taking money", "G4"},
    {"a7fd7be3-c87f-4499-b1c4-77722d392b85", "The growth loop in v1", "G5"},
    {"913e160d-fd58-4b34-ac08-95cd00d42b77", "Death and revival in fantasy", "G2"},
    {"fac66450-9fbe-4808-a2fd-1646fcbb23c2", "Migration and cutover from the old app", "G6"},
    {"67f341d3-1797-4b02-8a94-0e4b27e04f2f", "Closed beta design", "G5"},
    {"3f43237a-01b1-4329-bf3f-63b16b55ac39", "stakeholder presentation page", "G7"},
    {"9d737700-0f3d-4a5c-8a89-cdc26e9282e0", "Who came up with what", "G7"},
    {"e1fa4220-7e9e-43a2-924f-9ac3ebee11fa", "Work time auto log", "G7"},
    {"72996ae0-5af7-4e4c-b1a0-ab6d6330843a", "high vs low skills storytelling", "G2"},
    {"e423df4e-5ea4-4853-896e-c45f39e23f75", "Cards on mobile", "G7"},
    {"f9683a5d-ad23-48f3-89c4-b9b188e1366d", "Character creation", "G2"},
    {"eb7c0641-a3ed-4ac2-b002-ddff6dfe3fc2", "World building", "G2"},
    {"5448d20a-ebc6-4c36-bed6-56f37c57a66e", "Add animations to wiring section", "G7"},
    {"c2fe8263-8de0-441e-a3a1-79b13186b4ee", "check that founder page is up to date", "G7"},
    {"5c55bf37-8c6d-479b-a019-5466c66d0efd", "Who's online right now", "G7"},
    {"3acb46bc-742a-48bc-b54b-1fc9477ddb9e", "Chatt/Comment ping others", "G7"},
    {"9fb3b555-6144-46a3-81d0-35a6c0cba9a0", "Team chat with mentions", "G7"},
    {"9615a9bd-213b-4a25-bcca-434b962e58d5", "Writing in the comment field in cards", "G7"},
    {"b18fc8dc-97bb-4fda-a7fa-d90e47e94480", "Sorting button for Ideas", "G7"},
    {"989f1dc5-a732-450d-a3ee-c12b112f02ed", "Code heat map", "G7"},
    {"b96b9f95-bf82-466e-b700-418dc33d8130", "Screen capture in chat", "G7"},
    {"6d08cf7e-43ad-42d9-a050-c6ba1a10a3e8", "In game, scroll so the last text is visible", "G2"},
    {"8018439a-33c4-4950-a64c-0c99ca02fba3", "update presentation after shared workarea", "G7"},
    {"42fd5696-78dd-4551-bd7f-008ab7c37a76", "Refine ideation process", "G7"},
    {"2a7317de-e9f8-4bc5-8bca-25980adc306f", "Set the AI spend ceiling", "G3"}
  ]

  def up do
    create table(:board_goals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :title, :string, null: false
      add :outcome, :text, null: false, default: ""
      add :target_date, :date
      add :target_label, :string
      add :sort, :integer, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_goals, [:key])

    create table(:board_goal_votes, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :goal_id, references(:board_goals, type: :binary_id, on_delete: :delete_all),
        null: false

      add :founder, :string, null: false
      add :value, :integer, null: false
      add :reason, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_goal_votes, [:goal_id, :founder])

    create constraint(:board_goal_votes, :goal_vote_is_plus_or_minus_one,
             check: "value IN (-1, 1)"
           )

    create constraint(:board_goal_votes, :goal_downvote_has_reason,
             check: "value = 1 OR (reason IS NOT NULL AND btrim(reason) <> '')"
           )

    alter table(:board_ideas) do
      add :goal_id, references(:board_goals, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:board_ideas, [:goal_id])

    flush()

    for {key, title, outcome, date, label, sort} <- @goals do
      repo().query!(
        """
        INSERT INTO board_goals (id, key, title, outcome, target_date, target_label, sort, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4::text::date, $5, $6, now(), now())
        ON CONFLICT (key) DO NOTHING
        """,
        [key, title, outcome, date, label, sort]
      )
    end

    for {id, title, key} <- @cards do
      repo().query!(
        """
        UPDATE board_ideas SET goal_id = (SELECT id FROM board_goals WHERE key = $3)
        WHERE goal_id IS NULL
          AND (id::text = $1 OR (title = $2 AND NOT EXISTS (SELECT 1 FROM board_ideas WHERE id::text = $1)))
        """,
        [id, title, key]
      )
    end
  end

  def down do
    alter table(:board_ideas) do
      remove :goal_id
    end

    drop table(:board_goal_votes)
    drop table(:board_goals)
  end
end
