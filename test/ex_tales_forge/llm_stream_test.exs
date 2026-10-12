defmodule TalesForge.LLMStreamTest do
  use TalesForge.DataCase, async: false

  alias TalesForge.Schemas.AICall
  alias TalesForge.Game.Prompts
  alias TalesForge.Game.Schemas.{GMStructuredResponse, HandlerResult, PlayerAction, SingleAction}
  alias TalesForge.GameSessions
  alias TalesForge.LLM
  alias TalesForge.LLM.Stream, as: SSE

  doctest TalesForge.LLM.Stream

  # A fake xAI server. Each request takes the next script from the agent and
  # sends its chunks as server-sent events, with a short pause between chunks.
  defmodule FakeXAI do
    @behaviour Plug
    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts) do
      {:ok, body, conn} = read_body(conn)
      send(:persistent_term.get({__MODULE__, :test}), {:request, Jason.decode!(body)})

      chunks =
        Agent.get_and_update(:persistent_term.get({__MODULE__, :agent}), fn [c | r] -> {c, r} end)

      conn =
        conn
        |> put_resp_content_type("text/event-stream")
        |> send_chunked(200)

      Enum.reduce(chunks, conn, fn chunk, conn ->
        Process.sleep(15)
        {:ok, conn} = chunk(conn, chunk)
        conn
      end)
    end
  end

  setup do
    {:ok, session} = GameSessions.create_session(%{name: "Stream GM"})
    System.put_env("LLM_PROVIDER", "xai")
    System.put_env("XAI_API_KEY", "test-key")

    {:ok, server} = start_supervised({Bandit, plug: FakeXAI, ip: :loopback, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    old_req = Application.get_env(:ex_tales_forge, :llm_req_options)
    Application.put_env(:ex_tales_forge, :llm_req_options, [])
    Application.put_env(:ex_tales_forge, :xai_api_base, "http://127.0.0.1:#{port}/v1")
    Application.put_env(:ex_tales_forge, :llm_stream_throttle_ms, 0)
    :persistent_term.put({FakeXAI, :test}, self())

    on_exit(fn ->
      System.delete_env("LLM_PROVIDER")
      System.delete_env("XAI_API_KEY")
      Application.put_env(:ex_tales_forge, :llm_req_options, old_req)
      Application.delete_env(:ex_tales_forge, :xai_api_base)
      Application.delete_env(:ex_tales_forge, :llm_stream_throttle_ms)
    end)

    %{session: session}
  end

  defp script(replies) do
    {:ok, agent} = Agent.start_link(fn -> replies end)
    :persistent_term.put({FakeXAI, :agent}, agent)
  end

  # SSE chunks for `content`, split every `size` bytes, then usage and [DONE].
  defp sse(content, size \\ 7) do
    deltas =
      for piece <- split(content, size) do
        "data: " <> Jason.encode!(%{"choices" => [%{"delta" => %{"content" => piece}}]}) <> "\n\n"
      end

    usage = %{"prompt_tokens" => 100, "completion_tokens" => 42}

    deltas ++
      [
        "data: " <> Jason.encode!(%{"choices" => [], "usage" => usage}) <> "\n\n",
        "data: [DONE]\n\n"
      ]
  end

  defp split(<<>>, _size), do: []

  defp split(bin, size) when byte_size(bin) <= size, do: [bin]

  defp split(bin, size) do
    <<a::binary-size(size), rest::binary>> = bin
    [a | split(rest, size)]
  end

  defp gm_turn(session, opts \\ []) do
    test_pid = self()

    LLM.complete_turn(
      [
        %{role: "system", content: Prompts.gm_system()},
        %{role: "user", content: "RULES AND STATE"}
      ],
      %PlayerAction{overall_intent: "look around", action: %SingleAction{action_type: :observe}},
      %HandlerResult{handler: "observe"},
      1,
      Keyword.merge([session_id: session.id, on_text: &send(test_pid, {:stream, &1})], opts)
    )
  end

  defp stream_events(acc \\ []) do
    receive do
      {:stream, event} -> stream_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  test "streams the narrative as it arrives, then parses the whole reply", %{session: session} do
    narrative = "The lamp \"gutters\".\nA café door creaks."
    # Key order as the strict schema gives it: narrative first.
    reply = Jason.OrderedObject.new([{"narrative", narrative}, {"gm_notes", "n"}])
    script([sse(Jason.encode!(reply))])

    assert {:ok, %GMStructuredResponse{narrative: ^narrative, gm_notes: "n"}} =
             gm_turn(session, variant: :full)

    assert_received {:request, request}
    assert request["stream"] == true

    texts = for {:text, t} <- stream_events(), do: t
    assert length(texts) > 2
    # Each event has the whole text so far: every text starts the next one.
    assert texts
           |> Enum.chunk_every(2, 1, :discard)
           |> Enum.all?(fn [a, b] -> String.starts_with?(b, a) end)

    assert List.last(texts) == narrative

    [row] =
      Repo.all(from c in AICall, where: c.game_session_id == ^session.id and c.purpose == "gm")

    assert row.status == "ok"
    assert row.output_tokens == 42
    assert row.narration_variant == "full"
    assert is_integer(row.ttft_ms) and row.ttft_ms <= row.latency_ms
  end

  test "a JSON retry resets the streamed text and streams the new reply", %{session: session} do
    bad = ~s({"narrative":"First try that breaks",})
    good = Jason.encode!(%{"narrative" => "Second try."})
    script([sse(bad), sse(good)])

    assert {:ok, %GMStructuredResponse{narrative: "Second try."}} = gm_turn(session)

    events = stream_events()
    {before, [:reset | after_reset]} = Enum.split_while(events, &(&1 != :reset))
    assert Enum.all?(before, fn {:text, t} -> String.starts_with?("First try that breaks", t) end)
    assert after_reset != []
    assert Enum.all?(after_reset, fn {:text, t} -> String.starts_with?("Second try.", t) end)
    assert List.last(after_reset) == {:text, "Second try."}

    rows =
      Repo.all(from c in AICall, where: c.game_session_id == ^session.id and c.purpose == "gm")

    assert length(rows) == 2
  end

  test "the lean variant drops gm_notes and location_name from schema and prompt", %{
    session: session
  } do
    script([sse(Jason.encode!(%{"narrative" => "Rain."}))])

    assert {:ok, %GMStructuredResponse{narrative: "Rain.", gm_notes: nil}} =
             gm_turn(session, variant: :lean)

    assert_received {:request, request}
    props = request["response_format"]["json_schema"]["schema"]["properties"]
    assert Map.keys(props) |> Enum.sort() == ~w(context_summary narrative npc_memory_updates)
    [%{"content" => system} | _] = request["messages"]
    refute system =~ "gm_notes"
    refute system =~ "location_name"
    assert system =~ "Return ONLY valid JSON matching the required schema."
    assert request["max_tokens"] == TalesForge.Config.tier2_max_tokens()

    [row] =
      Repo.all(from c in AICall, where: c.game_session_id == ^session.id and c.purpose == "gm")

    assert row.narration_variant == "lean"
  end

  test "the full variant keeps the prompt byte for byte" do
    messages = [%{role: "system", content: Prompts.gm_system()}]
    assert LLM.gm_messages_for(messages, :full) == messages
  end

  test "each GM prompt file has the parts that the lean variant cuts" do
    for variant <- ["default", "baseline"] do
      prompt = Prompts.gm_system(variant)
      assert prompt =~ ~r/^- gm_notes:/m
      assert prompt =~ " Leave location_name out."
      [%{content: lean}] = LLM.gm_messages_for([%{role: "system", content: prompt}], :lean)
      refute lean =~ "gm_notes"
      refute lean =~ "location_name"
    end
  end

  test "the variant follows the app role" do
    assert LLM.gm_variant(:production) == :lean
    assert LLM.gm_variant(:playtest) == :full
    assert LLM.gm_variant(:local) == :full
  end

  describe "partial_narrative/1" do
    test "stops before an escape that is not complete" do
      assert SSE.partial_narrative(~s({"narrative":"a\\)) == "a"
      assert SSE.partial_narrative(~s({"narrative":"a\\ud83d)) == "a"
      assert SSE.partial_narrative(~s({"narrative":"a\\ud83d\\ude00b)) == "a😀b"
    end

    test "stops before a UTF-8 character that is not complete" do
      <<part::binary-size(1), _::binary>> = "é"
      assert SSE.partial_narrative(~s({"narrative":"caf) <> part) == "caf"
    end

    test "stops at the closing quote" do
      assert SSE.partial_narrative(~s({"narrative":"done","gm_notes":"x"})) == "done"
    end
  end

  test "events/1 keeps an event that is not complete" do
    {first, rest} = SSE.events("data: {\"a\"")
    assert first == []
    assert {[~s({"a":1})], ""} = SSE.events(rest <> ":1}\n\n")
  end
end
