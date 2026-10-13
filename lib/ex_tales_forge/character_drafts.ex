defmodule TalesForge.CharacterDrafts do
  @moduledoc """
  The server keeps one character draft for each player and adventure. From
  the first dice roll, the creation screen saves the draft after each change.
  The screen loads the draft on mount, so a reload keeps the dice roll. The screen deletes the draft when
  the adventure starts.

  `owner` is the signed-in player (the GitHub login, or the email).
  """

  import Ecto.Query

  alias TalesForge.CharacterCreation.Draft
  alias TalesForge.CharacterDrafts.StoredDraft
  alias TalesForge.Repo

  @doc "Returns the stored draft of `owner` for `adventure_id`, or `nil`."
  @spec get(String.t(), String.t()) :: Draft.t() | nil
  def get(owner, adventure_id) when is_binary(owner) and is_binary(adventure_id) do
    with %StoredDraft{draft: bin} <-
           Repo.get_by(StoredDraft, owner: owner, adventure_id: adventure_id),
         %Draft{adventure_id: ^adventure_id} = draft <- decode(bin) do
      upgrade(draft)
    else
      _ -> nil
    end
  end

  @doc "Saves `draft` for `owner`. A second save replaces the first."
  @spec put(String.t(), Draft.t()) :: :ok
  def put(owner, %Draft{} = draft) when is_binary(owner) do
    now = DateTime.utc_now()

    Repo.insert!(
      %StoredDraft{
        owner: owner,
        adventure_id: draft.adventure_id,
        draft: :erlang.term_to_binary(draft),
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [draft: :erlang.term_to_binary(draft), updated_at: now]],
      conflict_target: [:owner, :adventure_id]
    )

    :ok
  end

  @doc "Deletes the stored draft of `owner` for `adventure_id`."
  @spec delete(String.t(), String.t()) :: :ok
  def delete(owner, adventure_id) when is_binary(owner) and is_binary(adventure_id) do
    Repo.delete_all(
      from(d in StoredDraft, where: d.owner == ^owner and d.adventure_id == ^adventure_id)
    )

    :ok
  end

  # Only terms that use existing atoms decode. A bad term gives nil.
  defp decode(bin) do
    :erlang.binary_to_term(bin, [:safe])
  rescue
    ArgumentError -> nil
  end

  # A draft saved before a new field gets the default of that field.
  defp upgrade(%Draft{} = draft) do
    defaults = Map.from_struct(%Draft{adventure_id: draft.adventure_id, seed_key: draft.seed_key})
    struct(Draft, Map.merge(defaults, Map.from_struct(draft)))
  end
end
