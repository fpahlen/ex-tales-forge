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
          key: String.t(),
          kind: kind(),
          entity_id: String.t(),
          summary: String.t(),
          seed: map() | nil,
          session: map() | nil,
          label: String.t() | nil
        }

  @enforce_keys [:key, :kind, :entity_id, :summary]
  defstruct [:key, :kind, :entity_id, :summary, seed: nil, session: nil, label: nil]

  @doc "The difference kinds, in list order."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "The labels that the classifier can give to a `:free_text` difference."
  @spec labels() :: [String.t()]
  def labels, do: @labels

  @doc "Makes a difference. The key comes from the kind, the entity id and the session data."
  @spec new(kind(), String.t(), String.t(), map() | nil, map() | nil) :: t()
  def new(kind, entity_id, summary, seed, session) when kind in @kinds do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({entity_id, session}))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    %__MODULE__{
      key: "#{kind}:#{entity_id}:#{digest}",
      kind: kind,
      entity_id: entity_id,
      summary: summary,
      seed: seed,
      session: session
    }
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
