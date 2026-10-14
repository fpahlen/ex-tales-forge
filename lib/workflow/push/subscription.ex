defmodule Workflow.Push.Subscription do
  @moduledoc """
  One row of `push_subscriptions`: the web push subscription of one founder
  in one browser profile. The browser gives the `endpoint` and the two keys
  (`p256dh`, `auth`). The endpoint is unique. Times are UTC.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @schema_prefix "workflow"

  @typedoc "A push subscription row."
  @type t :: %__MODULE__{}

  schema "push_subscriptions" do
    field :handle, :string
    field :endpoint, :string
    field :p256dh, :string
    field :auth, :string
    field :user_agent, :string
    field :last_sent_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Checks the subscription that the browser gives. The endpoint must be an
  HTTPS URL.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:handle, :endpoint, :p256dh, :auth, :user_agent])
    |> validate_required([:handle, :endpoint, :p256dh, :auth])
    |> validate_length(:user_agent, max: 255)
    |> validate_length(:p256dh, max: 255)
    |> validate_length(:auth, max: 255)
    |> validate_change(:endpoint, fn :endpoint, url ->
      case URI.parse(url) do
        %URI{scheme: "https", host: host} when is_binary(host) and host != "" -> []
        _ -> [endpoint: "must be an https URL"]
      end
    end)
    |> unique_constraint(:endpoint)
  end
end
