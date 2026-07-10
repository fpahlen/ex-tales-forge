defmodule TalesForge.AdminResources do
  @moduledoc """
  Ash domain for admin surfaces.

  Contains resources used *only* by the admin UI and TalesForge.Admin context:
  - Authoring resources for pre-play content.
  - Runtime resources (GameSession, Turn, NpcInstance, Scene) over the existing
    runtime tables. These are for admin listing/editing only.

  Core game logic (play, Jido agents, Oban workers, GameSessions used by the
  play loop) MUST continue to use plain Ecto (TalesForge.Schemas.* + Repo)
  and must never depend on this domain.
  """

  use Ash.Domain, otp_app: :ex_tales_forge

  resources do
    # Runtime admin resources (over existing tables, admin-only)
    resource TalesForge.AdminResources.GameSession
    resource TalesForge.AdminResources.Turn
    resource TalesForge.AdminResources.NpcInstance
    resource TalesForge.AdminResources.Scene

    # Authoring resources (also exposed in admin)
    resource TalesForge.Authoring.Adventure
    resource TalesForge.Authoring.Location
    resource TalesForge.Authoring.NpcDefinition
  end
end
