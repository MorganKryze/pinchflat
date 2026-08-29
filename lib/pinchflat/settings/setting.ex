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
    :forced_download_priority,
    :download_backoff_enabled,
    :download_backoff_threshold,
    :download_backoff_minutes,
    :download_backoff_paused_until,
    :set_aside_permanent_failures,
    :restrict_filenames
  ]

  @required_fields [
    :onboarding,
    :pro_enabled,
    :video_codec_preference,
    :audio_codec_preference,
    :extractor_sleep_interval_seconds,
    :download_max_attempts,
    :forced_download_priority
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
    #
    # The defaults are upstream's: 20 is what Oban uses when a worker sets no limit, and a
    # nil backoff base means Oban's own backoff curve. Setting a base opts into this
    # fork's much longer one, which is built to outlast an IP throttle rather than to
    # recover from a blip - lower the attempt count if you do, because base * attempt^4
    # reaches absurd delays long before the twentieth try.
    field :download_max_attempts, :integer, default: 20
    field :download_retry_backoff_base_seconds, :integer
    # 5 is what the worker itself defaults to and what upstream inserts. 0 puts forced
    # retries in front of everything already queued.
    field :forced_download_priority, :integer, default: 5

    # Stopping the yt-dlp queues while YouTube is refusing us. Off by default: it is the
    # only thing here that stops work on its own, so it is opted into rather than
    # inherited on an update.
    field :download_backoff_enabled, :boolean, default: false
    field :download_backoff_threshold, :integer, default: 5
    field :download_backoff_minutes, :integer, default: 30
    # State rather than preference, kept in the open so "why is nothing downloading" has
    # an answer with a time on it instead of living inside a process.
    field :download_backoff_paused_until, :utc_datetime

    # Whether a failure that can never succeed takes the media item out of rotation for
    # good. Off by default: upstream reconsiders these at every index, which is a
    # defensible choice, since a video can be un-privated and an age restriction lifted.
    field :set_aside_permanent_failures, :boolean, default: false

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
    # Oban's own range.
    |> validate_number(:forced_download_priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 9)
    |> validate_number(:download_backoff_threshold, greater_than_or_equal_to: 1)
    |> validate_number(:download_backoff_minutes, greater_than_or_equal_to: 1)
  end
end
