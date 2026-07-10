defmodule TalesForge.Authoring.Location do
  @moduledoc """
  Ash resource for authored Locations (part of the world in an Adventure).

  Stores the stable authored data for places:
  - id, name, exits, blurb, fixtures, ground_items, scene_image_url (for Tigris)
  """

  use Ash.Resource,
    otp_app: :ex_tales_forge,
    domain: TalesForge.Authoring,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "locations"
    repo(TalesForge.Repo)
  end

  attributes do
    uuid_primary_key :id

    attribute :location_id, :string do
      allow_nil? false
      public? true
      description "Stable slug within the adventure, e.g. weary_pilgrim"
    end

    attribute :adventure_id, :string do
      allow_nil? false
      public? true
      description "Which adventure this location belongs to (e.g. crossroads_ledger)"
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :exits, {:array, :string} do
      public? true
      default []
    end

    attribute :blurb, :string do
      public? true
    end

    attribute :fixtures, {:array, :string} do
      public? true
      default []
    end

    attribute :ground_items, {:array, :map} do
      public? true
      default []
    end

    attribute :scene_image_url, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :location_id,
        :adventure_id,
        :name,
        :exits,
        :blurb,
        :fixtures,
        :ground_items,
        :scene_image_url
      ]
    end

    update :update do
      primary? true

      accept [
        :name,
        :exits,
        :blurb,
        :fixtures,
        :ground_items,
        :scene_image_url
      ]
    end
  end

  code_interface do
    define :create
    define :read
    define :update
    define :destroy
  end

  identities do
    identity :unique_location_in_adventure, [:adventure_id, :location_id]
  end
end
