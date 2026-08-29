defmodule Pinchflat.Downloading.MediaDownloadWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :media_fetching,
    priority: 5,
    unique: [period: :infinity, states: [:available, :scheduled, :retryable, :executing]],
    tags: ["media_item", "media_fetching", "show_in_dashboard"]

  require Logger

  alias __MODULE__
  alias Pinchflat.Tasks
  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Media
  alias Pinchflat.Media.FileSyncing
  alias Pinchflat.Downloading.MediaDownloader

  alias Pinchflat.Lifecycle.UserScripts.CommandRunner, as: UserScriptRunner

  @doc """
  Oban's own backoff unless a base is configured, in which case a much longer curve.

  Upstream leaves this alone, so nothing here changes until someone asks for it. What
  they would be asking for: the failures worth retrying on this queue clear on the scale
  of hours, not seconds, an IP throttle from YouTube being the common one. Oban's default
  packs its early attempts into about twenty minutes, which sits entirely inside a
  throttle window, so every attempt in it fails and the only thing they achieve is more
  requests against an IP that is already refusing us.

  With a base set the gaps are `base * attempt^4`, jittered - at 30 that is roughly 30s,
  8min, 40min then 2h. It grows fast, so lower the attempt limit alongside it.

  Read from the settings on every call rather than compiled in: how long a throttle lasts
  depends on the connection it is happening to, which is not something this code can know.

  Returns integer() (seconds)
  """
  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt} = job) do
    case Settings.get!(:download_retry_backoff_base_seconds) do
      nil -> super(job)
      base -> trunc(:math.pow(attempt, 4) * base * (0.9 + :rand.uniform() * 0.2))
    end
  end

  @doc """
  Starts the media_item media download worker and creates a task for the media_item.

  Returns {:ok, %Task{}} | {:error, :duplicate_job} | {:error, %Ecto.Changeset{}}
  """
  def kickoff_with_task(media_item, job_args \\ %{}, job_opts \\ []) do
    # Set here rather than in `use Oban.Worker` so it is a setting and not a recompile.
    # An explicit job_opts still wins, since a caller asking for something specific knows
    # more than the default does.
    job_opts = Keyword.put_new(job_opts, :max_attempts, Settings.get!(:download_max_attempts))

    %{id: media_item.id}
    |> Map.merge(job_args)
    |> MediaDownloadWorker.new(job_opts)
    |> Tasks.create_job_with_task(media_item)
  end

  @doc """
  For a given media item, download the media alongside any options.
  Does not download media if its source is set to not download media
  (unless forced).

  Options:
    - `force`: force download even if the source is set to not download media. Fully
      re-downloads media, including the video
    - `quality_upgrade?`: re-downloads media, including the video. Does not force download
      if the source is set to not download media

  Returns :ok | {:error, any, ...any}
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => media_item_id} = args}) do
    should_force = Map.get(args, "force", false)
    is_quality_upgrade = Map.get(args, "quality_upgrade?", false)

    media_item = fetch_and_run_prevent_download_user_script(media_item_id)

    if should_download_media?(media_item, should_force, is_quality_upgrade) do
      download_media_and_schedule_jobs(media_item, is_quality_upgrade, should_force)
    else
      :ok
    end
  rescue
    Ecto.NoResultsError -> Logger.info("#{__MODULE__} discarded: media item #{media_item_id} not found")
    Ecto.StaleEntryError -> Logger.info("#{__MODULE__} discarded: media item #{media_item_id} stale")
  end

  # If this is a quality upgrade, only check if the source is set to download media
  # or that the media item's download hasn't been prevented
  defp should_download_media?(media_item, should_force, true = _is_quality_upgrade) do
    (media_item.source.download_media && !media_item.prevent_download) || should_force
  end

  # If it's not a quality upgrade, additionally check if the media item is pending download
  defp should_download_media?(media_item, should_force, _is_quality_upgrade) do
    source = media_item.source
    is_pending = Media.pending_download?(media_item)

    (is_pending && source.download_media && !media_item.prevent_download) || should_force
  end

  # If a user script exists and, when run, returns a non-zero exit code, prevent this and all future downloads
  # of the media item.
  #
  # NOTE: this used to set prevent_download and nothing else - no log line, no stored
  # reason. A media item would go quiet forever and the only way to find out why was to
  # read the user's own script. The exit code is now recorded, because a media item that
  # will never be attempted again has to be able to say what stopped it.
  defp fetch_and_run_prevent_download_user_script(media_item_id) do
    media_item = Media.get_media_item!(media_item_id)

    {:ok, media_item} =
      case run_user_script(:media_pre_download, media_item) do
        {:ok, _, exit_code} when exit_code != 0 ->
          reason = "Blocked by the media_pre_download user script (exit code #{exit_code})"
          Logger.info("Media item ##{media_item.id}: #{reason}")

          Media.update_media_item(media_item, %{prevent_download: true, blocked_reason: reason})

        _ ->
          {:ok, media_item}
      end

    Repo.preload(media_item, :source)
  end

  defp download_media_and_schedule_jobs(media_item, is_quality_upgrade, should_force) do
    overwrite_behaviour = if should_force || is_quality_upgrade, do: :force_overwrites, else: :no_force_overwrites
    override_opts = [overwrite_behaviour: overwrite_behaviour]

    case MediaDownloader.download_for_media_item(media_item, override_opts) do
      {:ok, downloaded_media_item} ->
        {:ok, updated_media_item} =
          Media.update_media_item(downloaded_media_item, %{
            media_size_bytes: compute_media_filesize(downloaded_media_item),
            media_redownloaded_at: get_redownloaded_at(is_quality_upgrade)
          })

        :ok = FileSyncing.delete_outdated_files(media_item, updated_media_item)
        run_user_script(:media_downloaded, updated_media_item)

        :ok

      {:recovered, _media_item, _message} ->
        {:error, :retry}

      {:error, :unsuitable_for_download, _message} ->
        {:ok, :non_retry}

      {:error, _error_atom, message} ->
        action_on_error(message)
    end
  end

  defp compute_media_filesize(media_item) do
    case File.stat(media_item.media_filepath) do
      {:ok, %{size: size}} -> size
      _ -> nil
    end
  end

  defp get_redownloaded_at(true), do: DateTime.utc_now()
  defp get_redownloaded_at(_), do: nil

  defp action_on_error(message) do
    # This will attempt re-download at the next indexing, but it won't be retried
    # immediately as part of job failure logic
    #
    # NOTE: "Sign in to confirm" is deliberately not matched as a prefix. It covers two
    # opposite situations. "Sign in to confirm your age" needs the cookies of a verified
    # account and will never succeed without them, so it belongs here. "Sign in to confirm
    # you're not a bot" is an IP throttle that clears on its own within hours, and treating
    # it as final is what leaves media items carrying an error with no job left to retry
    # them: the worker returns {:ok, :non_retry}, so Oban records the job as a success and
    # nothing ever reconsiders the item until the next index.
    non_retryable_errors = [
      "Video unavailable",
      "Sign in to confirm your age",
      "This video is available to this channel's members"
    ]

    if String.contains?(to_string(message), non_retryable_errors) do
      Logger.error("yt-dlp download will not be retried: #{inspect(message)}")

      {:ok, :non_retry}
    else
      {:error, :download_failed}
    end
  end

  # NOTE: I like this pattern of using the default value so that I don't have to
  # define it in config.exs (and friends). Consider using this elsewhere.
  defp run_user_script(event, media_item) do
    runner = Application.get_env(:pinchflat, :user_script_runner, UserScriptRunner)

    runner.run(event, media_item)
  end
end
