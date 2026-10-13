defmodule TalesForge.GitEvents.Mapper do
  @moduledoc """
  Maps a GitHub webhook (the `X-GitHub-Event` name and the decoded JSON
  body) to a `TalesForge.GitEvents.GitEvent`. Pure; a malformed payload is
  ignored, never raised on.

  Events: `pull_request`, `push`, `workflow_run` and `check_suite`. Any
  other event (also `ping`) gives `:ignore`.
  """

  alias TalesForge.GitEvents.GitEvent

  @doc """
  The event, or `:ignore`.

      iex> {:ok, e} = TalesForge.GitEvents.Mapper.map("push", %{"ref" => "refs/heads/main",
      ...>   "after" => "ABC1234", "repository" => %{"full_name" => "o/r"},
      ...>   "sender" => %{"login" => "bobby"},
      ...>   "commits" => [%{"id" => "a1", "timestamp" => "2026-10-13T09:00:00Z"},
      ...>                 %{"id" => "ABC1234", "timestamp" => "2026-10-13T09:05:00+02:00"}]})
      iex> {e.type, e.repo, e.sha, e.branch, e.actor, Enum.map(e.commits, & &1.sha)}
      {:push, "o/r", "abc1234", "main", "bobby", ["abc1234", "a1"]}
      iex> TalesForge.GitEvents.Mapper.map("issues", %{"repository" => %{"full_name" => "o/r"}})
      :ignore
  """
  @spec map(String.t() | nil, term()) :: {:ok, GitEvent.t()} | :ignore
  def map(name, %{"repository" => %{"full_name" => repo}} = payload) when is_binary(repo) do
    case build(name, payload, repo) do
      %GitEvent{} = event -> {:ok, event}
      nil -> :ignore
    end
  rescue
    _malformed -> :ignore
  end

  def map(_name, _payload), do: :ignore

  defp build("pull_request", %{"pull_request" => %{} = pr} = p, repo) do
    pull = pull(pr)

    pull &&
      %GitEvent{
        type: :pull_request,
        action: text(p["action"]),
        repo: repo,
        pr: pull.number,
        sha: pull.head_sha,
        actor: login(p),
        at: pull.updated_at,
        branch: pr |> nested("base", "ref") |> text(),
        pull: pull
      }
  end

  defp build("push", %{"ref" => "refs/heads/" <> branch} = p, repo) do
    commits =
      for %{"id" => id} = c when is_binary(id) <- List.wrap(p["commits"]) do
        %{sha: String.downcase(id), at: time(c["timestamp"])}
      end

    %GitEvent{
      type: :push,
      repo: repo,
      sha: sha(p["after"]),
      actor: login(p) || p |> nested("pusher", "name") |> text(),
      at: p |> nested("head_commit", "timestamp") |> time(),
      branch: branch,
      commits: Enum.reverse(commits)
    }
  end

  defp build("workflow_run", %{"workflow_run" => %{} = run} = p, repo) do
    %GitEvent{
      type: :workflow_run,
      action: text(p["action"]),
      repo: repo,
      pr: first_pr(run),
      sha: sha(run["head_sha"]),
      actor: login(p),
      at: time(run["updated_at"]),
      branch: text(run["head_branch"]),
      workflow: text(run["name"]),
      ci: ci(run["status"], run["conclusion"])
    }
  end

  defp build("check_suite", %{"check_suite" => %{} = suite} = p, repo) do
    %GitEvent{
      type: :check_suite,
      action: text(p["action"]),
      repo: repo,
      pr: first_pr(suite),
      sha: sha(suite["head_sha"]),
      actor: login(p),
      at: time(suite["updated_at"]),
      branch: text(suite["head_branch"]),
      ci: ci(suite["status"], suite["conclusion"])
    }
  end

  defp build(_name, _payload, _repo), do: nil

  @doc """
  A pull request object (webhook or REST) in the shape of
  `t:TalesForge.PrFeed.pr/0`, or nil without a number. A closed pull request
  with `merged_at` is `:merged`.

      iex> pr = TalesForge.GitEvents.Mapper.pull(%{"number" => 3, "title" => "Inn",
      ...>   "state" => "closed", "merged_at" => "2026-10-09T09:00:00Z",
      ...>   "merge_commit_sha" => "ABC", "head" => %{"sha" => "def"}})
      iex> {pr.number, pr.state, pr.merge_sha, pr.head_sha}
      {3, :merged, "abc", "def"}
  """
  @spec pull(map()) :: map() | nil
  def pull(%{"number" => number} = pr) when is_integer(number) and number > 0 do
    merged_at = time(pr["merged_at"])

    %{
      number: number,
      title: text(pr["title"]) || "(no title)",
      author: pr |> nested("user", "login") |> text(),
      url: url(pr["html_url"]),
      state: state(pr["state"], merged_at),
      draft: pr["draft"] == true,
      head_sha: pr |> nested("head", "sha") |> sha(),
      merge_sha: if(merged_at, do: sha(pr["merge_commit_sha"])),
      created_at: time(pr["created_at"]),
      merged_at: merged_at,
      closed_at: time(pr["closed_at"]),
      updated_at: time(pr["updated_at"])
    }
  end

  def pull(_other), do: nil

  @doc """
  A run or suite status from GitHub's `status` and `conclusion`.

      iex> alias TalesForge.GitEvents.Mapper
      iex> {Mapper.ci("completed", "success"), Mapper.ci("completed", "timed_out"),
      ...>  Mapper.ci("completed", "skipped"), Mapper.ci("in_progress", nil)}
      {:passed, :failed, :cancelled, :running}
  """
  @spec ci(term(), term()) :: GitEvent.ci()
  def ci("completed", "success"), do: :passed

  def ci("completed", conclusion)
      when conclusion in ["failure", "timed_out", "startup_failure", "action_required"],
      do: :failed

  def ci("completed", _other), do: :cancelled
  def ci(_queued_or_running, _conclusion), do: :running

  defp state("open", _merged_at), do: :open
  defp state(_closed, nil), do: :closed
  defp state(_closed, _merged_at), do: :merged

  defp first_pr(%{"pull_requests" => [%{"number" => n} | _]}) when is_integer(n), do: n
  defp first_pr(_other), do: nil

  defp login(p), do: p |> nested("sender", "login") |> text()

  defp nested(map, outer, inner) do
    case map[outer] do
      %{} = sub -> sub[inner]
      _ -> nil
    end
  end

  defp sha(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp sha(_value), do: nil

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(_value), do: nil

  defp url("https://github.com/" <> _ = url), do: url
  defp url(_other), do: nil

  defp time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp time(_value), do: nil
end
