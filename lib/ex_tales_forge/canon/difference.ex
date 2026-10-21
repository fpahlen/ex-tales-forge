defmodule TalesForge.Canon.Difference do
  @moduledoc """
  One difference between a session and its seed.

  Kinds:

  - `:new_place`: the session has a place that the seed does not have.
  - `:changed_place`: the session and the seed give a place a different
    name or different exits.
  - `:new_entity`: the session has an NPC that the seed does not have.
  - `:new_fact`: the session holds a typed fact on a known entity, and the
    seed does not have that fact.
  - `:free_text`: the session holds a fact on an entity that neither the
    seed nor the session structure knows. The classifier gives it a `label`.

  `key` is stable for the same difference, so a founder decision stays on
  the row when the review runs again.
  """

  @kinds [:new_place, :changed_place, :new_entity, :new_fact, :free_text]
  @labels ~w(new_npc changed_place conflict other)

  @type kind :: :new_place | :changed_place | :new_entity | :new_fact | :free_text

  @type t :: %__MODULE__{
          key: String.t() | nil,
          kind: kind(),
          entity_id: String.t(),
          summary: String.t(),
          seed: map() | nil,
          session: map() | nil,
          label: String.t() | nil
        }

  @enforce_keys [:kind, :entity_id, :summary]
  defstruct [:kind, :entity_id, :summary, key: nil, seed: nil, session: nil, label: nil]

  @doc "The difference kinds, in list order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "The labels that the classifier can give to a `:free_text` difference."
  @spec labels() :: [String.t()]
  def labels, do: @labels

  @doc "Makes a difference: sets its key from the kind, the entity id and the session data."
  @spec new(t()) :: t()
  def new(%__MODULE__{kind: kind, entity_id: entity_id, session: session} = d)
      when kind in @kinds do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({entity_id, session}))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    %{d | key: "#{kind}:#{entity_id}:#{digest}"}
  end

  @doc "A plain map of the difference, for storage with a founder decision."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = d) do
    %{
      "key" => d.key,
      "kind" => Atom.to_string(d.kind),
      "entity_id" => d.entity_id,
      "summary" => d.summary,
      "seed" => d.seed,
      "session" => d.session,
      "label" => d.label
    }
  end
end
