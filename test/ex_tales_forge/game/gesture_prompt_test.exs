defmodule TalesForge.Game.GesturePromptTest do
  @moduledoc """
  The GM's recent gestures reach the next GM prompt as spent, in the per-turn
  part only; a repeat is logged.
  """
  use TalesForge.DataCase, async: false

  import ExUnit.CaptureLog
  import TalesForge.PlaytestHelpers, only: [stub_llm: 1]

  alias TalesForge.GameSessions

  @narrative "Brenna wipes her hands on her apron and leans an elbow on the bar."

  setup do
    mode = Application.get_env(:ex_tales_forge, :intent_jev)

    on_exit(fn ->
      if mode,
        do: Application.put_env(:ex_tales_forge, :intent_jev, mode),
        else: Application.delete_env(:ex_tales_forge, :intent_jev)

      System.put_env("LLM_PROVIDER", "mock")
      System.delete_env("XAI_API_KEY")
    end)

    Application.put_env(:ex_tales_forge, :intent_jev, :off)
    test_pid = self()

    stub_llm(fn
      :gm, user, system ->
        send(test_pid, {:gm_prompt, system, user})
        %{"narrative" => @narrative}

      _kind, _user, _system ->
        :default
    end)

    :ok
  end

  defp two_turns do
    {:ok, session} =
      GameSessions.create_session(%{adventure_id: "tin_valley"})

    assert {:ok, _} =
             GameSessions.submit_message(session.id, "I ask the innkeeper about the road")

    assert_received {:gm_prompt, _system, first_user}

    log =
      capture_log(fn ->
        assert {:ok, _} = GameSessions.submit_message(session.id, "I ask about the mine")
      end)

    assert_received {:gm_prompt, system, second_user}
    %{first: first_user, second: second_user, system: system, log: log}
  end

  test "default: the second GM prompt lists the first turn's gestures, and a repeat is logged" do
    %{first: first, second: second, system: system, log: log} = two_turns()

    refute first =~ "Gestures already used"

    assert second =~
             "## Gestures already used (recent turns)\n- wipes her hands\n- leans an elbow\n"

    assert system =~ ~s|Sometimes the per-turn state has "Gestures already used (recent turns)"|
    refute system =~ "Banned stock phrases"

    assert log =~ "gm gesture repeated"
    assert log =~ "key=wipe:hand"
    assert log =~ "key=lean:elbow"
  end

  test "default: the list sits in the per-turn message, after the session-stable part" do
    %{second: second} = two_turns()
    [stable | _] = String.split(second, "## Perceived facts")
    refute stable =~ "Gestures already used"
  end
end
