defmodule TalesForge.Workers.GenerateImage do
  @moduledoc """
  Oban worker for Phase 2 image generation / upload (Tigris).

  Placeholder implementation. Real version will:
  - Call image gen (xAI or other)
  - Upload to configured bucket
  - Patch the authored Ash resource with the resulting URL
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 3

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type, "target_id" => target}}) do
    Logger.info("images worker stub type=#{type} target=#{target} (no-op for now)")

    # Example future:
    # if type == "portrait", update Ash NpcDefinition...
    # if type == "scene", ...

    :ok
  end
end
