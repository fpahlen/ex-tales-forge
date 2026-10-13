defmodule Workflow.Team.Source do
  @moduledoc """
  The edge that reads the team config. The first source is the `workflow`
  block of `priv/team/data.json`, with the presentation text from
  `priv/team/content.json`.

  The files are read at compile time (`@external_resource`), like
  `TalesForge.TeamPage`. A request does no file IO, and a broken file fails
  the build. Only edge modules call `team/0`. They give the struct to the
  pure Workflow functions.
  """

  @data_path Path.expand("../../../priv/team/data.json", __DIR__)
  @content_path Path.expand("../../../priv/team/content.json", __DIR__)
  @external_resource @data_path
  @external_resource @content_path

  @team Workflow.Team.from_map(
          @data_path |> File.read!() |> Jason.decode!() |> Map.fetch!("workflow"),
          @content_path |> File.read!() |> Jason.decode!() |> Map.delete("_about")
        )

  @doc "The team config of this app."
  @spec team() :: Workflow.Team.t()
  def team, do: @team
end
