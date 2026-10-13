defmodule TalesForge.GitEvents.GitEvent do
  @moduledoc """
  One GitHub webhook delivery as plain data (`TalesForge.GitEvents.Mapper.map/2`).

  - `type`: `:pull_request`, `:push`, `:workflow_run` or `:check_suite`.
  - `action`: the payload's `action` (`"opened"`, `"completed"`, ...); nil for a push.
  - `repo`: `owner/name`.
  - `pr`: the pull request number, or nil.
  - `sha`: the head commit (a pull request's head, a push's new tip, a run's
    or a suite's head commit), lowercase.
  - `actor`: the GitHub login that caused the event.
  - `at`: when it happened, or nil.
  - `branch`: the branch (`"main"` for a push to main), or nil.
  - `workflow`: the workflow name of a run (`"CI"`, `"Deploy to playtest"`), or nil.
  - `ci`: the run or suite status (`:passed`, `:failed`, `:running`,
    `:cancelled`), or nil.
  - `pull`: a pull request event's pull request, in the shape of
    `t:TalesForge.PrFeed.pr/0`, or nil.
  - `commits`: a push's commits, newest first (`%{sha, at}`); `[]` otherwise.
  """

  @enforce_keys [:type, :repo]
  defstruct type: nil,
            action: nil,
            repo: nil,
            pr: nil,
            sha: nil,
            actor: nil,
            at: nil,
            branch: nil,
            workflow: nil,
            ci: nil,
            pull: nil,
            commits: []

  @typedoc "The event types the app reads."
  @type type :: :pull_request | :push | :workflow_run | :check_suite

  @typedoc "A run or suite status."
  @type ci :: :passed | :failed | :running | :cancelled | nil

  @typedoc "One GitHub event."
  @type t :: %__MODULE__{
          type: type(),
          action: String.t() | nil,
          repo: String.t(),
          pr: pos_integer() | nil,
          sha: String.t() | nil,
          actor: String.t() | nil,
          at: DateTime.t() | nil,
          branch: String.t() | nil,
          workflow: String.t() | nil,
          ci: ci(),
          pull: map() | nil,
          commits: [%{sha: String.t(), at: DateTime.t() | nil}]
        }
end
