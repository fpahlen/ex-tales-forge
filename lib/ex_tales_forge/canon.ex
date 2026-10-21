defmodule TalesForge.Canon do
  @moduledoc """
  Session versus canon: the founder review of one session against its
  world seed.

  1. `review/1` reads the seed (`TalesForge.Canon.Seed`) and the session
     (`TalesForge.Canon.SessionSnapshot`), runs the pure diff
     (`TalesForge.Canon.Diff`) and labels the leftover free text with one
     classifier call (`TalesForge.Canon.Classifier`).
  2. `decide/1` stores the founder decision on one difference
     (`TalesForge.Canon.Decision`). No decision changes the session or the
     seed files. "Add to canon" stores a proposed seed patch
     (`TalesForge.Canon.SeedPatch`) for a pull request.

  A founder starts the review with a button on the admin page. The turn
  pipeline never calls this module.
  """

  import Ecto.Query

  alias TalesForge.Canon.{
    Classifier,
    Decision,
    Diff,
    Difference,
    Ruling,
    Seed,
    SessionSnapshot
  }

  alias TalesForge.Repo
  alias TalesForge.Schemas.GameSession

  @typedoc "The result of `review/1`."
  @type review :: %{
          differences: [Difference.t()],
          decisions: %{String.t() => Decision.t()},
          labels: :ok | :error
        }

  @doc """
  Reviews one session. `labels` is `:error` when the classifier call
  failed; the free-text rows then have no label.
  """
  @spec review(GameSession.t()) :: review()
  def review(%GameSession{} = session) do
    seed = Seed.load(session.world_state || %{})

    {status, differences} =
      session
      |> SessionSnapshot.from_session()
      |> Diff.diff(seed)
      |> Classifier.label(session.id)

    %{differences: differences, decisions: decisions(session.id), labels: status}
  end

  @doc "The stored decisions of a session, by difference key."
  @spec decisions(String.t()) :: %{String.t() => Decision.t()}
  def decisions(session_id) do
    Repo.all(from d in Decision, where: d.game_session_id == ^session_id)
    |> Map.new(&{&1.diff_key, &1})
  end

  @doc """
  Stores the founder decision on one difference. `action` is
  `"session_only"`, `"add_to_canon"` or `"error"`. A later decision on the
  same difference replaces the earlier one.
  """
  @spec decide(Ruling.t()) :: {:ok, Decision.t()} | {:error, Ecto.Changeset.t()}
  def decide(%Ruling{} = ruling) do
    ruling
    |> Ruling.decision()
    |> Repo.insert(
      on_conflict: {:replace, [:action, :founder, :difference, :seed_patch, :updated_at]},
      conflict_target: [:game_session_id, :diff_key],
      returning: true
    )
  end
end
