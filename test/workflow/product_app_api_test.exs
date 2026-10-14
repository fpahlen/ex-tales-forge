defmodule Workflow.ProductAppApiTest do
  @moduledoc """
  Workflow split 4/5: Workflow reads costs, online players and the running
  commit from the product app, and the product app pushes work-log turn
  events to Workflow. One token for each direction.
  """
  use TalesForgeWeb.ConnCase, async: false

  alias TalesForge.DeployLanes.DataBoundary
  alias TalesForge.ProductApi
  alias TalesForge.Repo
  alias TalesForge.GameSessions
  alias TalesForge.Schemas.{AICall, PlaytestRun, PlaytestScore}
  alias TalesForge.Workers.PushWorkLogTurn
  alias TalesForge.WorkflowClient
  alias TalesForge.WorkLog
  alias TalesForge.WorkLog.Event
  alias Workflow.ProductApp

  @product_token "product-token-for-tests"
  @workflow_token "workflow-token-for-tests"
  @founder "ada@example.com"

  setup do
    on_exit(fn ->
      for key <- [:product_api, :workflow_api, ProductApp, WorkflowClient],
          do: Application.delete_env(:ex_tales_forge, key)

      System.delete_env("GIT_SHA")
    end)

    :ok
  end

  defp call(method, path, token, body \\ nil) do
    conn =
      build_conn()
      |> then(&if(token, do: put_req_header(&1, "authorization", "Bearer " <> token), else: &1))

    case method do
      :get -> get(conn, path)
      :post -> post(conn, path, body)
    end
  end

  defp insert_cost! do
    Repo.insert!(%AICall{
      purpose: "intent",
      status: "ok",
      call_type: "jev",
      model: "jev",
      latency_ms: 250,
      cost_micro_usd: 1_500_000,
      started_at: DateTime.utc_now()
    })
  end

  defp insert_scores! do
    {:ok, session} = GameSessions.create_session(%{name: "Scores", adventure_id: "tin_valley"})

    run =
      Repo.insert!(%PlaytestRun{
        game_session_id: session.id,
        persona: "paul",
        module: "tin_valley",
        build: "0.1.0",
        git_sha: "2a6589edcfcb2066731d951a7cd6c7fe45bdebd4",
        flags: %{},
        turn_limit: 2,
        turns_played: 2,
        status: "finished",
        stop_reason: "turn_limit",
        started_at: ~U[2026-10-08 10:00:00Z],
        finished_at: ~U[2026-10-08 10:05:00Z]
      })

    for {turn, overall, confidence} <- [{1, 4.0, 0.75}, {2, 2.0, 0.25}] do
      Repo.insert!(%PlaytestScore{
        playtest_run_id: run.id,
        kind: "turn_affect",
        source: "jev",
        model: "jev",
        rubric_version: "paul-v2",
        turn_number: turn,
        overall: overall,
        confidence: confidence,
        scores: %{}
      })
    end
  end

  describe "product-app API (GET /internal/product/*)" do
    test "off (404) while PRODUCT_APP_API_TOKEN is unset; 401 with a wrong token" do
      for path <-
            ~w(/internal/product/costs /internal/product/online /internal/product/running-commits /internal/product/persona-scores) do
        assert call(:get, path, @product_token).status == 404
      end

      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)

      for path <-
            ~w(/internal/product/costs /internal/product/online /internal/product/running-commits /internal/product/persona-scores) do
        assert call(:get, path, nil).status == 401
        assert call(:get, path, "wrong").status == 401
      end
    end

    test "the old peer token does not open the product-app API" do
      Application.put_env(:ex_tales_forge, :costs_peer, token: "peer")
      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)
      assert call(:get, "/internal/product/costs", "peer").status == 401
    after
      Application.delete_env(:ex_tales_forge, :costs_peer)
    end

    test "answers costs, online and running commits with the right token" do
      insert_cost!()
      System.put_env("GIT_SHA", "abcdef1234567")
      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)

      costs = call(:get, "/internal/product/costs", @product_token) |> json_response(200)
      assert %{"spend" => %{"total_usd" => 1.5}, "intent_latency" => %{"reads" => 1}} = costs

      assert %{"people" => people} =
               call(:get, "/internal/product/online", @product_token) |> json_response(200)

      assert is_list(people)

      assert %{"current" => "abcdef1234567"} =
               call(:get, "/internal/product/running-commits", @product_token)
               |> json_response(200)
    end
  end

  describe "Workflow.ProductApp" do
    test "the local and the HTTP adapter give the same data" do
      insert_cost!()
      System.put_env("GIT_SHA", "abcdef1234567")
      now = DateTime.utc_now()

      local = {ProductApp.costs(now), ProductApp.online(), ProductApp.running_commits()}
      assert {%{spend: %{"total_usd" => 1.5}}, _, %{current: "abcdef1234567"}} = local

      Application.put_env(:ex_tales_forge, ProductApp,
        adapter: ProductApp.Http,
        base_url: "https://product.example"
      )

      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)

      Req.Test.stub(ProductApp.Http, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> @product_token]

        body =
          case conn.request_path do
            "/internal/product/costs" -> ProductApi.costs(now)
            "/internal/product/online" -> ProductApi.online()
            "/internal/product/running-commits" -> ProductApi.running_commits()
          end

        Req.Test.json(conn, body)
      end)

      assert {ProductApp.costs(now), ProductApp.online(), ProductApp.running_commits()} == local
    end

    test "the local and the HTTP adapter give the same persona scores" do
      assert ProductApp.persona_scores() == nil
      insert_scores!()

      local = ProductApp.persona_scores()

      assert %{runs: 1, by_persona: %{"paul" => %{score: 3.5, low_confidence_pct: 50, turns: 2}}} =
               local

      Application.put_env(:ex_tales_forge, ProductApp,
        adapter: ProductApp.Http,
        base_url: "https://product.example"
      )

      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)

      assert %{"scores" => %{"runs" => 1}} =
               call(:get, "/internal/product/persona-scores", @product_token)
               |> json_response(200)

      Req.Test.stub(ProductApp.Http, fn conn ->
        assert conn.request_path == "/internal/product/persona-scores"
        Req.Test.json(conn, ProductApi.persona_scores())
      end)

      assert ProductApp.persona_scores() == local

      assert %{source: :live, runs: 1} = TalesForgeWeb.TeamLiveNumbers.persona_scores(%{})
    end

    test "the HTTP adapter gives empty data without a token or when the product app fails" do
      Application.put_env(:ex_tales_forge, ProductApp,
        adapter: ProductApp.Http,
        base_url: "https://product.example"
      )

      assert ProductApp.costs() == %{spend: nil, intent_latency: nil}

      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)
      Req.Test.stub(ProductApp.Http, &Req.Test.transport_error(&1, :timeout))
      assert ProductApp.online() == %{people: []}
      assert ProductApp.running_commits() == %{current: nil, production: nil, playtest: nil}
      assert ProductApp.persona_scores() == nil
    end
  end

  describe "work-log turn events (POST /internal/workflow/work-log/turns)" do
    @event %{
      "founder" => @founder,
      "ref" => "turn-1",
      "at" => "2026-10-13T10:00:00Z",
      "app" => "production"
    }

    test "off (404) while WORKFLOW_API_TOKEN is unset; 401 with a wrong token" do
      path = "/internal/workflow/work-log/turns"
      assert call(:post, path, @workflow_token, @event).status == 404

      Application.put_env(:ex_tales_forge, :workflow_api, token: @workflow_token)
      Application.put_env(:ex_tales_forge, :product_api, token: @product_token)
      assert call(:post, path, nil, @event).status == 401
      assert call(:post, path, @product_token, @event).status == 401
    end

    test "stores the event one time; a bad body is 422" do
      Application.put_env(:ex_tales_forge, :workflow_api, token: @workflow_token)
      path = "/internal/workflow/work-log/turns"

      assert %{"result" => "stored"} =
               call(:post, path, @workflow_token, @event) |> json_response(200)

      assert %{"result" => "skipped"} =
               call(:post, path, @workflow_token, @event) |> json_response(200)

      assert [%Event{founder: @founder, kind: "turn", ref: "turn-1", app: "production"}] =
               TalesForge.Workflow.Repo.all(Event)

      assert call(:post, path, @workflow_token, %{"ref" => "x"}).status == 422
    end

    test "the push job: no job for a turn without a founder; the local adapter stores the event" do
      assert PushWorkLogTurn.job(%{id: "t", founder: nil, inserted_at: DateTime.utc_now()}) == nil

      %Ecto.Changeset{changes: %{args: args}} =
        PushWorkLogTurn.job(%{
          id: "t-2",
          founder: @founder,
          inserted_at: ~U[2026-10-13 10:00:00Z]
        })

      assert :ok = perform_job(PushWorkLogTurn, args)
      assert :ok = perform_job(PushWorkLogTurn, args)
      assert [%Event{ref: "t-2"}] = TalesForge.Workflow.Repo.all(Event)
    end

    test "the HTTP adapter posts with WORKFLOW_API_TOKEN; a failure makes the job retry" do
      Application.put_env(:ex_tales_forge, WorkflowClient,
        adapter: WorkflowClient.Http,
        base_url: "https://workflow.example"
      )

      assert {:error, :no_token} = perform_job(PushWorkLogTurn, @event)

      Application.put_env(:ex_tales_forge, :workflow_api, token: @workflow_token)

      Req.Test.stub(WorkflowClient.Http, fn conn ->
        assert conn.request_path == "/internal/workflow/work-log/turns"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> @workflow_token]
        Req.Test.json(conn, %{"result" => "stored"})
      end)

      assert :ok = perform_job(PushWorkLogTurn, @event)

      Req.Test.stub(WorkflowClient.Http, &Plug.Conn.send_resp(&1, 503, ""))
      assert {:error, {:status, 503}} = perform_job(PushWorkLogTurn, @event)
    end

    test "receive_turn/1 skips a bot and refuses a bad event" do
      assert {:ok, :skipped} = WorkLog.receive_turn(%{@event | "founder" => "bot:case"})
      assert {:error, :invalid} = WorkLog.receive_turn(%{@event | "at" => "yesterday"})
      assert {:error, :invalid} = WorkLog.receive_turn(%{@event | "app" => "other"})
    end
  end

  describe "the data boundary" do
    test "Workflow calls the product app only through the local adapter" do
      boundary = DataBoundary.default_path() |> File.read!() |> DataBoundary.parse()
      assert boundary.pending == []
      assert boundary.adapter == ["lib/workflow/product_app/local.ex"]

      sets = %{
        workflow:
          MapSet.new(["lib/ex_tales_forge/team_online.ex", "lib/workflow/product_app/local.ex"]),
        wiring: MapSet.new(),
        pending: MapSet.new(boundary.adapter),
        workflow_data: MapSet.new(),
        product_data:
          MapSet.new(["lib/ex_tales_forge/online.ex", "lib/ex_tales_forge/product_api.ex"])
      }

      assert DataBoundary.violations(sets, [
               {"lib/ex_tales_forge/team_online.ex", "lib/ex_tales_forge/online.ex"},
               {"lib/workflow/product_app/local.ex", "lib/ex_tales_forge/product_api.ex"}
             ]) == [
               %{
                 kind: :workflow_to_product,
                 from: "lib/ex_tales_forge/team_online.ex",
                 to: "lib/ex_tales_forge/online.ex"
               }
             ]
    end
  end

  defp perform_job(worker, args), do: Oban.Testing.perform_job(worker, args, repo: Repo)
end
