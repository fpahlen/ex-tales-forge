defmodule TalesForge.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use TalesForge.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TalesForge.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import TalesForge.DataCase
    end
  end

  setup tags do
    TalesForge.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TalesForge.Repo, shared: not tags[:async])

    on_exit(fn ->
      stop_world_instances()
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Saves a session changeset with its characters, the way the turn does
  (`TalesForge.GameCharacter.Store.save_session/1`), so a test can set up
  `world_state["character"]`: the column is stored without it.
  """
  def save_session!(%Ecto.Changeset{} = changeset) do
    {:ok, session} = TalesForge.GameCharacter.Store.save_session(changeset)
    session
  end

  @doc """
  Writes `value` under `key` straight into the session's `world_state`
  column, past `TalesForge.Schemas.WorldState`: a session stored before
  step 10b-2, or a corrupt one.
  """
  def put_stored_world!(session_id, key, value) do
    TalesForge.Repo.query!(
      "UPDATE game_sessions SET world_state = jsonb_set(world_state, $1, $2) WHERE id = $3",
      [[key], value, Ecto.UUID.dump!(session_id)]
    )

    :ok
  end

  # The test's TalesForge.World.Instance processes, before the sandbox owner
  # goes (they read the database when they start and after each turn).
  defp stop_world_instances do
    TalesForge.World.Registry
    |> Registry.select([{{{:instance, :_}, :"$1", :_}, [], [:"$1"]}])
    |> Enum.each(&DynamicSupervisor.terminate_child(TalesForge.World.Supervisor, &1))
  end
end
