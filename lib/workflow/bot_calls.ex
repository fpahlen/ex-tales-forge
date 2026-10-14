defmodule Workflow.BotCalls do
  @moduledoc """
  The time of each bot's latest call to the board or chat API, for "who is
  online" (`TalesForge.TeamOnline`). Workflow owns this data.

  This process owns one ETS table. The API controllers write to it with
  `seen/1`. A restart clears it.
  """

  use GenServer

  @table __MODULE__

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Notes that `bot` made an API call now."
  @spec seen(atom()) :: :ok
  def seen(bot) when is_atom(bot), do: seen(bot, DateTime.utc_now())

  @doc "Notes that `bot` made an API call at `at`."
  @spec seen(atom(), DateTime.t()) :: :ok
  def seen(bot, %DateTime{} = at) when is_atom(bot) do
    if :ets.whereis(@table) != :undefined, do: :ets.insert(@table, {bot, at})
    :ok
  end

  @doc "The time of each bot's latest API call since this app started."
  @spec calls() :: %{optional(atom()) => DateTime.t()}
  def calls do
    if :ets.whereis(@table) == :undefined,
      do: %{},
      else: @table |> :ets.tab2list() |> Map.new()
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end
end
