defmodule TalesForge.GitEventsTest do
  @moduledoc "GitHub webhook signature and the mapping of each event type."
  use ExUnit.Case, async: true

  alias TalesForge.GitEvents.GitEvent
  alias TalesForge.GitEvents.Mapper
  alias TalesForge.GitEvents.Signature

  doctest TalesForge.GitEvents.Signature
  doctest TalesForge.GitEvents.Mapper

  @repo %{"full_name" => "whyse-ab/ex-tales-forge"}
  @sender %{"login" => "bobby"}

  describe "Signature.valid?/3" do
    test "accepts the signature of the exact body" do
      body = ~s({"zen":"Keep it simple."})
      assert Signature.valid?("s3cret", body, Signature.sign("s3cret", body))
    end

    test "refuses a changed body, another secret, a bad header and a blank secret" do
      body = ~s({"a":1})
      good = Signature.sign("s3cret", body)
      refute Signature.valid?("s3cret", body <> " ", good)
      refute Signature.valid?("other", body, good)
      refute Signature.valid?("s3cret", body, "sha1=" <> String.duplicate("0", 40))
      refute Signature.valid?("s3cret", body, "")
      refute Signature.valid?("", body, Signature.sign("", body))
      refute Signature.valid?(nil, body, good)
    end
  end

  describe "Mapper.map/2" do
    test "pull_request" do
      payload = %{
        "action" => "closed",
        "repository" => @repo,
        "sender" => @sender,
        "pull_request" => %{
          "number" => 240,
          "title" => "Perf",
          "state" => "closed",
          "html_url" => "https://github.com/whyse-ab/ex-tales-forge/pull/240",
          "merged_at" => "2026-10-13T09:50:00Z",
          "merge_commit_sha" => "C8DC2B9",
          "updated_at" => "2026-10-13T09:50:00Z",
          "head" => %{"sha" => "793DD50"},
          "base" => %{"ref" => "main"},
          "user" => %{"login" => "fpahlen"}
        }
      }

      assert {:ok, %GitEvent{} = e} = Mapper.map("pull_request", payload)

      assert %{
               type: :pull_request,
               action: "closed",
               repo: "whyse-ab/ex-tales-forge",
               pr: 240,
               sha: "793dd50",
               actor: "bobby",
               at: ~U[2026-10-13 09:50:00Z],
               branch: "main"
             } = e

      assert %{state: :merged, merge_sha: "c8dc2b9", author: "fpahlen"} = e.pull
    end

    test "push" do
      payload = %{
        "ref" => "refs/heads/main",
        "after" => "bbb2222",
        "repository" => @repo,
        "sender" => @sender,
        "head_commit" => %{"timestamp" => "2026-10-13T10:00:00Z"},
        "commits" => [
          %{"id" => "aaa1111", "timestamp" => "2026-10-13T09:59:00Z"},
          %{"id" => "bbb2222", "timestamp" => "2026-10-13T10:00:00Z"}
        ]
      }

      assert {:ok, e} = Mapper.map("push", payload)

      assert {e.type, e.sha, e.branch, e.at} ==
               {:push, "bbb2222", "main", ~U[2026-10-13 10:00:00Z]}

      assert Enum.map(e.commits, & &1.sha) == ["bbb2222", "aaa1111"]
    end

    test "workflow_run" do
      payload = %{
        "action" => "completed",
        "repository" => @repo,
        "sender" => @sender,
        "workflow_run" => %{
          "name" => "CI",
          "head_sha" => "abc1234",
          "head_branch" => "feat/x",
          "status" => "completed",
          "conclusion" => "failure",
          "updated_at" => "2026-10-13T10:01:00Z",
          "pull_requests" => [%{"number" => 242}]
        }
      }

      assert {:ok, e} = Mapper.map("workflow_run", payload)

      assert %{type: :workflow_run, workflow: "CI", ci: :failed, pr: 242, sha: "abc1234"} = e
      assert e.branch == "feat/x"
    end

    test "check_suite" do
      payload = %{
        "action" => "completed",
        "repository" => @repo,
        "sender" => @sender,
        "check_suite" => %{
          "head_sha" => "abc1234",
          "head_branch" => "main",
          "status" => "completed",
          "conclusion" => "success",
          "pull_requests" => []
        }
      }

      assert {:ok, %{type: :check_suite, ci: :passed, pr: nil, sha: "abc1234"}} =
               Mapper.map("check_suite", payload)
    end

    test "ignores unknown events, ping and malformed payloads" do
      assert Mapper.map("ping", %{"zen" => "x", "repository" => @repo}) == :ignore
      assert Mapper.map("star", %{"repository" => @repo}) == :ignore

      assert Mapper.map("pull_request", %{"repository" => @repo, "pull_request" => %{}}) ==
               :ignore

      assert Mapper.map("push", %{"no" => "repo"}) == :ignore
      assert Mapper.map(nil, nil) == :ignore
    end
  end
end
