defmodule TalesForge.Canon.Classifier do
  @moduledoc """
  The edge for the model call of the session review: it labels the
  `:free_text` differences with one label from
  `TalesForge.Canon.Difference.labels/0`.

  The adapter (`TalesForge.Canon.Classifier.Adapter`) comes from
  `config :ex_tales_forge, :canon_classifier, ...` (default
  `TalesForge.Canon.Classifier.Jev`). The adapter returns labels only. It
  writes no canon text.
  """

  alias TalesForge.Canon.Difference

  @doc """
  Labels the `:free_text` differences in the list with one adapter call.
  Other differences stay as they are. A label outside the fixed set becomes
  `"other"`. On an adapter error, the differences keep no label.
  """
  @spec label([Difference.t()], String.t()) :: {:ok | :error, [Difference.t()]}
  def label(differences, session_id) do
    items =
      for %Difference{kind: :free_text} = d <- differences,
          do: %{key: d.key, entity_id: d.entity_id, text: to_string(d.session["text"])}

    case items do
      [] -> {:ok, differences}
      items -> apply_labels(adapter().classify(items, session_id), differences)
    end
  end

  defp apply_labels({:ok, labels}, differences) do
    {:ok,
     Enum.map(differences, fn
       %Difference{kind: :free_text} = d -> %{d | label: fixed(Map.get(labels, d.key))}
       d -> d
     end)}
  end

  defp apply_labels({:error, _reason}, differences), do: {:error, differences}

  defp fixed(nil), do: nil
  defp fixed(label) when is_atom(label), do: fixed(Atom.to_string(label))
  defp fixed(label), do: if(label in Difference.labels(), do: label, else: "other")

  defp adapter,
    do: Application.get_env(:ex_tales_forge, :canon_classifier, TalesForge.Canon.Classifier.Jev)
end
