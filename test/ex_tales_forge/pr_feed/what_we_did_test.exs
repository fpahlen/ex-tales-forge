defmodule TalesForge.PrFeed.WhatWeDidTest do
  # The cache is global (:persistent_term), so not async.
  use ExUnit.Case, async: false

  alias TalesForge.PrFeed
  alias TalesForge.PrFeed.WhatWeDid
  alias TalesForge.PrFeed.WhatWeDidLLM

  doctest WhatWeDid

  @repo "https://github.com/org/product"
  # Wed 14 Oct 2026, 10:00 Stockholm time.
  @now ~U[2026-10-14 08:00:00Z]

  # A fixed PR feed snapshot: the pulls as the poller parses them.
  @pulls [
    %{
      number: 261,
      title: "Chat threads: notify every participant",
      merged_at: ~U[2026-10-14 03:00:00Z]
    },
    %{number: 260, title: "Product-app API: persona scores", merged_at: ~U[2026-10-13 18:00:00Z]},
    %{
      number: 257,
      title: "Workflow split 4/5: product-app API",
      merged_at: ~U[2026-10-12 06:00:00Z]
    },
    # Sun 11 Oct 23:30 Stockholm: before the window.
    %{number: 256, title: "Thread unread counts", merged_at: ~U[2026-10-11 21:30:00Z]},
    %{number: 258, title: "Open, not merged", merged_at: nil, state: :open}
  ]

  @base %{
    author: nil,
    draft: false,
    head_sha: nil,
    merge_sha: nil,
    closed_at: nil,
    created_at: ~U[2026-10-01 00:00:00Z],
    updated_at: nil
  }

  defp snapshot do
    pulls =
      Enum.map(@pulls, fn pr ->
        @base |> Map.merge(%{state: :merged, url: "#{@repo}/pull/#{pr.number}"}) |> Map.merge(pr)
      end)

    other =
      Map.merge(@base, %{
        number: 9,
        title: "Docs",
        state: :merged,
        url: "https://github.com/org/docs/pull/9",
        merged_at: ~U[2026-10-14 07:00:00Z]
      })

    PrFeed.build(%{pulls: [other | pulls]}, @now)
  end

  defp merged, do: snapshot().merged

  defp llm(reply) do
    test = self()

    fn system, user, _opts ->
      send(test, {:llm_called, system, user})
      reply
    end
  end

  setup do
    WhatWeDid.clear_cache()
    on_exit(&WhatWeDid.clear_cache/0)
  end

  test "the snapshot keeps the merged pull requests of the last 7 days, newest first" do
    assert Enum.map(merged(), & &1.number) == [9, 261, 260, 257, 256]
  end

  test "the window: the product repo, since midnight 2 days ago, Stockholm time" do
    assert Enum.map(WhatWeDid.window(merged(), @repo, @now), & &1.number) == [261, 260, 257]
    assert WhatWeDid.since_date(@now) == ~D[2026-10-12]
  end

  test "one model call makes the bullets, and each bullet links to its pull requests" do
    reply =
      {:ok,
       %{
         "bullets" => [
           %{"text" => "Chat threads notify each participant.", "prs" => [261]},
           %{
             "text" => "The product app gives persona scores to the team tools.",
             "prs" => [260, 257]
           }
         ]
       }}

    summary = WhatWeDid.summary(merged(), @now, repo_url: @repo, llm: llm(reply))

    assert_received {:llm_called, system, user}
    assert system == WhatWeDid.system_prompt()

    assert user ==
             "#261 Chat threads: notify every participant\n#260 Product-app API: persona scores\n#257 Workflow split 4/5: product-app API"

    assert summary == %{
             source: :ai,
             count: 3,
             since: ~D[2026-10-12],
             bullets: [
               %{
                 text: "Chat threads notify each participant.",
                 prs: [%{number: 261, url: "#{@repo}/pull/261"}]
               },
               %{
                 text: "The product app gives persona scores to the team tools.",
                 prs: [
                   %{number: 260, url: "#{@repo}/pull/260"},
                   %{number: 257, url: "#{@repo}/pull/257"}
                 ]
               }
             ]
           }
  end

  test "a bullet never starts with \"The team\"" do
    reply = {:ok, %{"bullets" => [%{"text" => "The team adds chat threads.", "prs" => [261]}]}}
    summary = WhatWeDid.summary(merged(), @now, repo_url: @repo, llm: llm(reply))
    assert [%{text: "Adds chat threads."}] = summary.bullets
    refute WhatWeDid.system_prompt() =~ "what the team made"
  end

  test "the result is cached for the day and the set of pull requests" do
    reply = {:ok, %{"bullets" => [%{"text" => "Work.", "prs" => [261, 260, 257]}]}}
    first = WhatWeDid.summary(merged(), @now, repo_url: @repo, llm: llm(reply))
    assert_received {:llm_called, _, _}

    later = DateTime.add(@now, 3600)
    assert WhatWeDid.summary(merged(), later, repo_url: @repo, llm: llm(reply)) == first
    assert WhatWeDid.cached_or_titles(merged(), later, repo_url: @repo) == first
    refute_received {:llm_called, _, _}

    # A new merge: a new call.
    new = [%{number: 262, title: "New", url: "#{@repo}/pull/262", merged_at: later} | merged()]
    WhatWeDid.summary(new, later, repo_url: @repo, llm: llm(reply))
    assert_received {:llm_called, _, _}

    # A new day: a new call.
    WhatWeDid.summary(new, DateTime.add(@now, 86_400), repo_url: @repo, llm: llm(reply))
    assert_received {:llm_called, _, _}
  end

  test "a failed call, a bad answer or a raise gives the plain titles" do
    for reply <- [{:error, :timeout}, {:ok, %{"bullets" => []}}, {:ok, %{"x" => 1}}] do
      WhatWeDid.clear_cache()
      summary = WhatWeDid.summary(merged(), @now, repo_url: @repo, llm: llm(reply))
      assert summary.source == :titles

      assert [%{text: "Chat threads: notify every participant", prs: [%{number: 261}]} | _] =
               summary.bullets

      assert length(summary.bullets) == 3
    end

    WhatWeDid.clear_cache()
    raise_llm = fn _, _, _ -> raise "boom" end
    assert %{source: :titles} = WhatWeDid.summary(merged(), @now, repo_url: @repo, llm: raise_llm)
  end

  test "with the model call off, no call and the plain titles" do
    summary = WhatWeDid.summary(merged(), @now, repo_url: @repo, ai: false, llm: llm({:ok, %{}}))
    refute_received {:llm_called, _, _}
    assert %{source: :titles, count: 3} = summary
  end

  test "no merged pull requests: no call" do
    assert %{source: :titles, count: 0, bullets: []} =
             WhatWeDid.summary([], @now, repo_url: @repo, llm: llm({:ok, %{}}))

    refute_received {:llm_called, _, _}
  end

  test "without a call, the panel is the cached one or the plain titles" do
    assert %{source: :titles, count: 3} =
             WhatWeDid.cached_or_titles(merged(), @now, repo_url: @repo)
  end

  test "the repo comes from the team config by default" do
    repo = Workflow.Team.Source.team().repo_url
    pr = %{number: 5, title: "T", url: repo <> "/pull/5", merged_at: @now}
    assert %{count: 1} = WhatWeDid.summary([pr], @now, ai: false)
  end

  describe "WhatWeDidLLM" do
    setup do
      Application.put_env(:ex_tales_forge, :what_we_did_req_options,
        plug: {Req.Test, WhatWeDidLLM}
      )

      Application.put_env(:ex_tales_forge, :xai_api_key, "test-key")

      on_exit(fn ->
        Application.delete_env(:ex_tales_forge, :what_we_did_req_options)
        Application.delete_env(:ex_tales_forge, :xai_api_key)
      end)
    end

    test "sends the prompt with a JSON schema and decodes the answer" do
      Req.Test.stub(WhatWeDidLLM, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        body = Jason.decode!(body)
        assert body["response_format"]["json_schema"]["name"] == "what_we_did"

        assert [%{"role" => "system"}, %{"role" => "user", "content" => "#1 A"}] =
                 body["messages"]

        Req.Test.json(conn, %{
          "choices" => [%{"message" => %{"content" => ~s({"bullets":[{"text":"A.","prs":[1]}]})}}]
        })
      end)

      assert WhatWeDidLLM.complete("system", "#1 A") ==
               {:ok, %{"bullets" => [%{"text" => "A.", "prs" => [1]}]}}
    end

    test "an HTTP error gives an error" do
      Req.Test.stub(WhatWeDidLLM, &Plug.Conn.send_resp(&1, 500, "no"))
      assert WhatWeDidLLM.complete("s", "u") == {:error, {:http, 500}}
    end

    test "no key gives an error" do
      Application.put_env(:ex_tales_forge, :xai_api_key, "")
      previous = System.get_env("XAI_API_KEY")
      System.delete_env("XAI_API_KEY")
      on_exit(fn -> if previous, do: System.put_env("XAI_API_KEY", previous) end)
      assert WhatWeDidLLM.complete("s", "u") == {:error, :no_key}
    end
  end
end
