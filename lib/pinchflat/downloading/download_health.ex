defmodule Pinchflat.Downloading.DownloadHealth do
  @moduledoc """
  Answers, from the database, whether downloading is actually working.

  Every number here is derived from rows that already exist. That is deliberate: an
  in-memory counter would be the obvious way to track "failures in the last hour", and it
  would reset on every restart - which, on an instance that restarts when downloading goes
  wrong, is exactly when the number matters. `media_downloaded_at`, `last_error` and
  `last_error_at` already record it and already survive.

  Nothing here changes anything. It measures.
  """

  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Tasks.Task
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Settings
  alias Pinchflat.Downloading.DownloadErrors
  alias Pinchflat.YoutubeStatus.Switches

  # Oban states in which a job will still run. Anything else - completed, discarded,
  # cancelled - means nothing is going to pick that media item up again on its own.
  @live_job_states ~w(available scheduled executing retryable)

  # Counted separately because it is the only failure that says "stop asking": every
  # other kind is worth retrying immediately, this one is worth waiting out. The pattern
  # comes from DownloadErrors so the count and the behaviour cannot disagree about what a
  # throttle is - this one matches in SQL, so it needs the string rather than classify/1.

  @doc """
  The message a throttle carries, for the callers that match in SQL.

  Returns binary()
  """
  def throttle_error, do: DownloadErrors.throttle_pattern()

  @doc """
  A snapshot of whether downloads are getting through.

  Returns map()
  """
  def summary(window_hours \\ 1) do
    since = DateTime.add(DateTime.utc_now(), -window_hours, :hour)

    %{
      window_hours: window_hours,
      downloads_in_window: downloads_since(since),
      failures_in_window: failures_since(since),
      throttle_failures_in_window: throttle_failures_since(since),
      last_successful_download_at: last_successful_download_at(),
      pending_without_job: pending_without_job_count(),
      set_aside_without_reason: set_aside_without_reason_count(),
      yt_dlp_version: Settings.get!(:yt_dlp_version),
      yt_dlp_last_update_attempted_at: Settings.get!(:yt_dlp_last_update_attempted_at),
      yt_dlp_last_update_error: Settings.get!(:yt_dlp_last_update_error),
      # nil unless the yt-dlp queues are currently stopped. The one field here that says
      # "nothing is downloading and that is on purpose".
      queues_paused_until: Settings.get!(:download_backoff_paused_until),
      # Whether that pause ends on the clock or on an answer.
      backoff_probe_enabled: Settings.get!(:download_backoff_probe_enabled),
      # The other reason nothing is downloading, and the one no amount of waiting fixes.
      indexing_paused: Switches.paused?(:indexing),
      downloading_paused: Switches.paused?(:downloading)
    }
  end

  @doc """
  How many media items finished downloading since the given time.

  Returns integer()
  """
  def downloads_since(%DateTime{} = since) do
    MediaItem
    |> where([mi], mi.media_downloaded_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @doc """
  How many media items recorded a download failure since the given time.

  Returns integer()
  """
  def failures_since(%DateTime{} = since) do
    MediaItem
    |> where([mi], mi.last_error_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @doc """
  How many of those failures were YouTube throttling the IP.

  Returns integer()
  """
  def throttle_failures_since(%DateTime{} = since) do
    MediaItem
    |> where([mi], mi.last_error_at >= ^since and like(mi.last_error, ^"%#{DownloadErrors.throttle_pattern()}%"))
    |> Repo.aggregate(:count)
  end

  @doc """
  When the last download succeeded, or nil if none ever has. An old value here says more
  than any error count: it is the one number that cannot be argued with.

  Returns %DateTime{} | nil
  """
  def last_successful_download_at do
    MediaItem
    |> select([mi], max(mi.media_downloaded_at))
    |> Repo.one()
  end

  @doc """
  Media items that should be downloaded and have no job that will ever do it.

  This is the hole that made the whole fork necessary: a worker treating a failure as
  final returned `{:ok, :non_retry}`, Oban recorded a success, and the media item sat
  there with an error and nothing left to retry it. It has been fixed at the source, but
  the number belongs here because a silent hole is exactly what nobody thinks to check.

  Returns integer()
  """
  def pending_without_job_count do
    # ponytail: a NOT IN over a subquery rather than a correlated EXISTS. Simpler to
    # read, and on a library of a few thousand rows SQLite does not care. Revisit if it
    # ever shows up in a slow query log.
    media_items_with_live_jobs =
      from(t in Task,
        join: j in assoc(t, :job),
        where: j.state in ^@live_job_states and not is_nil(t.media_item_id),
        select: t.media_item_id
      )

    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^MediaQuery.pending())
    |> where([mi], mi.id not in subquery(media_items_with_live_jobs))
    |> Repo.aggregate(:count)
  end

  @doc """
  Media items set aside with nothing recording why.

  Should be zero for anything set aside automatically. A non-zero count means either a
  media item was set aside by hand, or something is still doing it silently.

  Returns integer()
  """
  def set_aside_without_reason_count do
    MediaItem
    |> where([mi], mi.prevent_download == true and is_nil(mi.blocked_reason))
    |> Repo.aggregate(:count)
  end
end
