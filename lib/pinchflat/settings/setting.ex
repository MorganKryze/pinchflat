defmodule Pinchflat.Settings.Setting do
  @moduledoc """
  The Setting schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @allowed_fields [
    :onboarding,
    :pro_enabled,
    :yt_dlp_version,
    :yt_dlp_last_update_attempted_at,
    :yt_dlp_last_update_error,
    :apprise_version,
    :apprise_server,
    :video_codec_preference,
    :audio_codec_preference,
    :youtube_api_key,
    :extractor_sleep_interval_seconds,
    :download_throughput_limit,
    :download_max_attempts,
    :download_retry_backoff_base_seconds,
    :restrict_filenames
  ]

  @required_fields [
    :onboarding,
    :pro_enabled,
    :video_codec_preference,
    :audio_codec_preference,
    :extractor_sleep_interval_seconds,
    :download_max_attempts,
    :download_retry_backoff_base_seconds
  ]

  schema "settings" do
    field :onboarding, :boolean, default: true
    field :pro_enabled, :boolean, default: false
    field :yt_dlp_version, :string
    field :yt_dlp_last_update_attempted_at, :utc_datetime
    # nil means the last attempt succeeded
    field :yt_dlp_last_update_error, :string
    field :apprise_version, :string
    field :apprise_server, :string
    field :youtube_api_key, :string
    field :route_token, :string
    field :extractor_sleep_interval_seconds, :integer, default: 0
    # This is a string because it accepts values like "100K" or "4.2M"
    field :download_throughput_limit, :string
    field :restrict_filenames, :boolean, default: false

    # How hard to keep trying a download that failed. Read when the job runs, not when it
    # is compiled, so a change takes effect on the next attempt without a restart.
    field :download_max_attempts, :integer, default: 5
    field :download_retry_backoff_base_seconds, :integer, default: 30

    field :video_codec_preference, :string
    field :audio_codec_preference, :string
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @allowed_fields)
    |> validate_required(@required_fields)
    |> validate_number(:extractor_sleep_interval_seconds, greater_than_or_equal_to: 0)
    # 1 means "try once and stop", which is a legitimate choice. 0 would mean Oban never
    # runs the job at all, which is not a setting anyone wants by accident.
    |> validate_number(:download_max_attempts, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> validate_number(:download_retry_backoff_base_seconds, greater_than_or_equal_to: 1)
  end
end
