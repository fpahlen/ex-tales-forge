defmodule TalesForge.Prompt.Section do
  @moduledoc """
  One part of a prompt (`TalesForge.Prompt`).

    * `id/0` — a stable atom, for tests and logs;
    * `slot/0` — `:static` (a system message), `:session` (stable for the
      session) or `:turn` (changes each turn);
    * `applies?/1` — false leaves the section out;
    * `render/1` — the text, or nil.

  The optional `glue/0` is the text before the section when it follows
  another section in the same message (default `separator/0`).
  """

  alias TalesForge.Prompt.Ctx

  @type slot :: :static | :session | :turn

  @callback id() :: atom()
  @callback slot() :: slot()
  @callback applies?(Ctx.t()) :: boolean()
  @callback render(Ctx.t()) :: String.t() | nil
  @callback glue() :: String.t()
  @optional_callbacks glue: 0

  @separator "\n\n---\n\n"

  @doc "The separator between two sections of one user message."
  @spec separator() :: String.t()
  def separator, do: @separator

  @doc "The glue before `section`."
  @spec glue(module()) :: String.t()
  def glue(section) do
    if function_exported?(section, :glue, 0),
      do: section.glue(),
      else: @separator
  end

  @doc false
  defmacro __using__(opts) do
    id = Keyword.fetch!(opts, :id)
    slot = Keyword.fetch!(opts, :slot)

    quote do
      @behaviour TalesForge.Prompt.Section

      @impl true
      def id, do: unquote(id)

      @impl true
      def slot, do: unquote(slot)

      @impl true
      def applies?(_ctx), do: true

      defoverridable applies?: 1
    end
  end
end
