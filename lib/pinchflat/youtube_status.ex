defmodule Pinchflat.YoutubeStatus do
  @moduledoc """
  Whether YouTube is answering this instance, read from work it was already doing.

  ## Why a status can be told at all

  A block is not on or off. Measured on one address inside one minute: indexing a
  collection worked, the pre-download check answered `No title found in player response`,
  and the download itself answered `Sign in to confirm you're not a bot`. Capabilities
  fail in the order of how much they ask for, so "partly working" is a real reading rather
  than a hedge.

  ## Where the readings come from

  Nothing here reaches out to YouTube and nothing new is recorded on the hot path. A
  download that worked already stamps `media_items.media_downloaded_at`; one that failed
  already stamps `last_error` and `last_error_at`; an indexing run already leaves a row in
  `oban_jobs` saying whether it completed. The sampler reads those every few minutes and
  writes down what it found.

  It has to write it down because nothing else keeps it. A media item holds only its
  *last* error, and Oban prunes finished jobs, so a block that started at 2am and cleared
  by 7am leaves no trace anywhere by the time anyone looks.

  ## Why `:idle` exists

  A window where nothing was attempted says nothing about YouTube. On a library that has
  caught up with its sources that is most windows, and calling them green would report a
  download path that was never exercised. Green means a download got through.
  """

  import Ecto.Query, warn: false

  alias Pinchflat.Repo
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Downloading.DownloadErrors
  alias Pinchflat.YoutubeStatus.StatusSample

  # Both indexing workers, named as strings because that is how Oban stores them. Only
  # these two talk to YouTube to list a collection; `remote_metadata` is not here because
  # the pre-download check runs inside the download worker and so is already counted as a
  # download failure.
  @indexing_workers [
    "Pinchflat.SlowIndexing.MediaCollectionIndexingWorker",
    "Pinchflat.FastIndexing.FastIndexingWorker"
  ]

  # Must match the crontab entry in runtime.exs. The window is normally the gap since the
  # previous sample, so a missed run widens the window rather than losing the time.
  @interval_seconds 300
  # After a stop, the gap since the last sample can be days. Counting all of it would
  # blame this minute for a fortnight of history, so the window is capped and the missing
  # time simply has no sample - which is what a gap in the history bar should mean.
  @max_window_seconds 3600
  # Same retention as Oban's own pruner, so the history and the jobs behind it disappear
  # together instead of leaving samples nothing can explain.
  @retention_days 30

  @doc """
  How often the sampler is meant to run, in seconds.

  Returns integer()
  """
  def interval_seconds, do: @interval_seconds

  @doc """
  Measures the time since the last sample and writes a new one.

  Returns {:ok, %StatusSample{}} | {:error, %Ecto.Changeset{}}
  """
  def sample!(now \\ DateTime.utc_now()) do
    since = window_start(now)
    counts = measure(since, now)

    %StatusSample{}
    |> StatusSample.changeset(
      Map.merge(counts, %{
        state: state_for(counts),
        window_seconds: DateTime.diff(now, since)
      })
    )
    |> Repo.insert()
  end

  @doc """
  What happened between two times, counted from rows that already existed.

  Returns map()
  """
  def measure(%DateTime{} = since, %DateTime{} = until) do
    errors = download_errors_between(since, until)

    %{
      downloads: downloads_between(since, until),
      download_failures: length(errors),
      # `retryable?/1` is false for exactly the failures that are a verdict on one video -
      # age gates, members-only, unavailable. Everything else, including messages this
      # does not recognise, could be YouTube refusing the address, and an unrecognised
      # message during a block is precisely what the pre-download check produced.
      connection_failures: Enum.count(errors, &DownloadErrors.retryable?/1),
      throttle_failures: Enum.count(errors, &DownloadErrors.throttled?/1),
      indexing_successes: indexing_successes_between(since, until),
      indexing_failures: indexing_failures_between(since, until)
    }
  end

  @doc """
  The reading a set of counts adds up to.

  Green needs a download that got through - nothing weaker proves the download path works.
  Red needs both tiers refusing, since indexing that still answers is the whole difference
  between degraded and blocked.

  Returns atom()
  """
  def state_for(counts) do
    %{
      downloads: downloads,
      connection_failures: connection_failures,
      indexing_successes: indexing_successes,
      indexing_failures: indexing_failures
    } = counts

    cond do
      downloads > 0 -> :nominal
      connection_failures > 0 && indexing_failures > 0 && indexing_successes == 0 -> :blocked
      connection_failures > 0 || indexing_failures > 0 -> :degraded
      true -> :idle
    end
  end

  @doc """
  The most recent sample, or nil if none has been taken.

  Returns %StatusSample{} | nil
  """
  def latest_sample do
    StatusSample
    |> order_by([s], desc: s.inserted_at, desc: s.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Samples from the last N hours, oldest first, as the history bar reads them.

  Returns [%StatusSample{}]
  """
  def history(hours \\ 24) do
    since = DateTime.add(DateTime.utc_now(), -hours, :hour)

    StatusSample
    |> where([s], s.inserted_at >= ^since)
    |> order_by([s], asc: s.inserted_at, asc: s.id)
    |> Repo.all()
  end

  @doc """
  Deletes samples older than the retention window.

  Returns {integer(), nil}
  """
  def prune! do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)

    StatusSample
    |> where([s], s.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  defp window_start(now) do
    earliest = DateTime.add(now, -@max_window_seconds, :second)

    case latest_sample() do
      nil -> DateTime.add(now, -@interval_seconds, :second)
      sample -> Enum.max([sample.inserted_at, earliest], DateTime)
    end
  end

  defp downloads_between(since, until) do
    MediaItem
    |> where([mi], mi.media_downloaded_at >= ^since and mi.media_downloaded_at < ^until)
    |> Repo.aggregate(:count)
  end

  # The messages themselves rather than a count, because what separates a refused address
  # from a private video is the text, and a window holds few enough rows to classify in
  # Elixir instead of teaching SQL the same table.
  defp download_errors_between(since, until) do
    MediaItem
    |> where([mi], mi.last_error_at >= ^since and mi.last_error_at < ^until)
    |> select([mi], mi.last_error)
    |> Repo.all()
  end

  defp indexing_successes_between(since, until) do
    Oban.Job
    |> where([j], j.worker in @indexing_workers and j.state == "completed")
    |> where([j], j.completed_at >= ^since and j.completed_at < ^until)
    |> Repo.aggregate(:count)
  end

  # `retryable` and `discarded` are the two states a failed job lands in, and `attempted_at`
  # is when it last tried. A job that fails and later succeeds is counted in the window it
  # failed in, which is the point.
  defp indexing_failures_between(since, until) do
    Oban.Job
    |> where([j], j.worker in @indexing_workers and j.state in ["retryable", "discarded"])
    |> where([j], j.attempted_at >= ^since and j.attempted_at < ^until)
    |> Repo.aggregate(:count)
  end
end
