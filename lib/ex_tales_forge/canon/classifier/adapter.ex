defmodule TalesForge.Canon.Classifier.Adapter do
  @moduledoc """
  The behaviour of a `TalesForge.Canon.Classifier` adapter (the Jev adapter,
  the test stub). A leaf: adapters and the classifier both depend on it.
  """

  @typedoc "One leftover item: the difference key, the entity id and the session text."
  @type item :: %{key: String.t(), entity_id: String.t(), text: String.t()}

  @doc "Labels the items in one call. Returns a label for each key that the adapter labelled."
  @callback classify([item()], session_id :: String.t()) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}
end
