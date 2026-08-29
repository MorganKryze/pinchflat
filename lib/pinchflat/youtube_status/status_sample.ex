defmodule Pinchflat.YoutubeStatus.StatusSample do
  @moduledoc """
  One reading of how the connection to YouTube behaved over one window of time.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @allowed_fields [
    :state,
    :downloads,
    :download_failures,
    :connection_failures,
    :throttle_failures,
    :indexing_successes,
    :indexing_failures,
    :window_seconds
  ]

  @required_fields [:state, :window_seconds]

  schema "youtube_status_samples" do
    field :state, Ecto.Enum, values: [:nominal, :degraded, :blocked, :idle]
    field :downloads, :integer, default: 0
    field :download_failures, :integer, default: 0
    field :connection_failures, :integer, default: 0
    field :throttle_failures, :integer, default: 0
    field :indexing_successes, :integer, default: 0
    field :indexing_failures, :integer, default: 0
    field :window_seconds, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(status_sample, attrs) do
    status_sample
    |> cast(attrs, @allowed_fields)
    |> validate_required(@required_fields)
  end
end
