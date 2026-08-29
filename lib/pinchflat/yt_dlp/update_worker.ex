defmodule Pinchflat.YtDlp.UpdateWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :local_data,
    # A failed update is worth retrying - the usual cause is a transient network
    # problem - but this runs daily, so there is no sense in Oban's default twenty
    # attempts chasing a failure that the next day's run will retry anyway.
    max_attempts: 3,
    tags: ["local_data"]

  require Logger

  alias __MODULE__
  alias Pinchflat.Settings
  alias Pinchflat.Utils.StringUtils

  @doc """
  Starts the yt-dlp update worker. Does not attach it to a task like `kickoff_with_task/2`

  Returns {:ok, %Oban.Job{}} | {:error, %Ecto.Changeset{}}
  """
  def kickoff do
    Oban.insert(UpdateWorker.new(%{}))
  end

  @doc """
  Updates yt-dlp and saves the version, and what the update itself did, to the settings.

  This worker is scheduled to run via the Oban Cron plugin as well as on app boot.

  The result of `update/0` used to be discarded, which made a failing self-update
  completely invisible: the job returned `:ok` whatever happened, so Oban recorded a
  success every day while the shipped yt-dlp stayed exactly as old as the image. yt-dlp
  falls behind a YouTube that changes every couple of weeks, and an out-of-date yt-dlp
  reports "Sign in to confirm you're not a bot", which reads like an IP ban and sends
  you looking in the wrong place entirely.

  Returns :ok | {:error, binary()}
  """
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Updating yt-dlp")

    update_result = yt_dlp_runner().update()

    # Asked for regardless of the outcome: a failed update leaves the previous binary in
    # place, and its version is still the one that matters.
    {:ok, yt_dlp_version} = yt_dlp_runner().version()
    Settings.set(yt_dlp_version: yt_dlp_version)
    Settings.set(yt_dlp_last_update_attempted_at: DateTime.utc_now())

    case update_result do
      {:ok, _output} ->
        Settings.set(yt_dlp_last_update_error: nil)

        :ok

      {:error, output} ->
        message = StringUtils.wrap_string(output)
        Logger.error("yt-dlp update failed: #{inspect(message)}")
        Settings.set(yt_dlp_last_update_error: message)

        # Returned rather than swallowed so the job lands in Oban as a failure. A daily
        # job that reports success while doing nothing is the whole defect being fixed.
        {:error, message}
    end
  end

  defp yt_dlp_runner do
    Application.get_env(:pinchflat, :yt_dlp_runner)
  end
end
