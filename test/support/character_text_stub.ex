defmodule TalesForge.CharacterTextStub do
  @moduledoc """
  A test adapter for `TalesForge.CharacterCreation.FromText`. Set the reply
  with `put/1`: a map, or a function of `(system, user)` that returns
  `{:ok, map}` or `{:error, reason}`. Each call sends
  `{:character_text_call, user}` to the test process that called `put/1`.
  """
  @behaviour TalesForge.CharacterCreation.FromText.Adapter

  @doc "Uses this stub with `reply` for the current test."
  def put(reply) do
    Application.put_env(:ex_tales_forge, :character_text_adapter, __MODULE__)
    Application.put_env(:ex_tales_forge, :character_text_stub, {self(), reply})
    ExUnit.Callbacks.on_exit(fn -> reset() end)
  end

  @doc "Goes back to the default adapter."
  def reset do
    Application.delete_env(:ex_tales_forge, :character_text_adapter)
    Application.delete_env(:ex_tales_forge, :character_text_stub)
  end

  @doc "A full reply with one confidence for each label."
  def reply(attrs \\ %{}, confidence \\ 0.9) do
    l = fn v -> %{"value" => v, "confidence" => confidence} end

    Map.merge(
      %{
        "name" => l.("Mira Vale"),
        "race" => l.("elf"),
        "class" => l.("ranger"),
        "occupation" => l.("hunter"),
        "stats" => [
          %{"stat" => "STR", "value" => 10},
          %{"stat" => "DEX", "value" => 16},
          %{"stat" => "CON", "value" => 12},
          %{"stat" => "INT", "value" => 11},
          %{"stat" => "WIS", "value" => 14},
          %{"stat" => "CHA", "value" => 10}
        ],
        "stats_confidence" => confidence,
        "skills" => [],
        "skills_confidence" => 0.0,
        "questions" => []
      },
      attrs
    )
  end

  @impl true
  def read(system, user) do
    {pid, reply} = Application.fetch_env!(:ex_tales_forge, :character_text_stub)
    send(pid, {:character_text_call, user})

    case reply do
      f when is_function(f, 2) -> f.(system, user)
      map -> {:ok, map}
    end
  end
end
