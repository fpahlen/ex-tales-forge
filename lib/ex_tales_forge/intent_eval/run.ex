defmodule TalesForge.IntentEval.Run do
  @moduledoc """
  One intent evaluation run (`TalesForge.IntentEval.run/1`): the `split`, the
  `readers`, the fixture `items`, the `worlds` they play in, what each reader
  read (`scored`), the `metrics` per reader and the run `opts`.
  """

  defstruct split: "tune", readers: [], items: [], worlds: %{}, scored: [], metrics: %{}, opts: []

  @type t :: %__MODULE__{
          split: String.t(),
          readers: [atom()],
          items: [map()],
          worlds: map(),
          scored: [map()],
          metrics: %{atom() => map()},
          opts: keyword()
        }
end
