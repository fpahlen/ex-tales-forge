defmodule TalesForge.Canon.ClassifierStub do
  @moduledoc """
  Test adapter of `TalesForge.Canon.Classifier`. It sends
  `{:canon_classify, items}` to the pid in the `:canon_stub_pid` app env and
  returns the reply in `:canon_stub_reply`: a function of the items, or
  `{:error, reason}`. The default gives every item the label `"other"`.
  """

  @behaviour TalesForge.Canon.Classifier.Adapter

  @impl true
  def classify(items, _session_id) do
    if pid = Application.get_env(:ex_tales_forge, :canon_stub_pid),
      do: send(pid, {:canon_classify, items})

    case Application.get_env(:ex_tales_forge, :canon_stub_reply) do
      {:error, _} = error -> error
      fun when is_function(fun, 1) -> {:ok, fun.(items)}
      nil -> {:ok, Map.new(items, &{&1.key, "other"})}
    end
  end
end
