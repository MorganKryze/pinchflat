defmodule Pinchflat.Downloading.ResumeQueuesWorker do
  @moduledoc """
  Ends a backoff pause, either because the time is up or because YouTube answered.

  ## Why scheduling cancels first

  The scheduled job is what actually resumes; the `download_backoff_paused_until` setting
  only describes it. Two writers can reach `schedule_for/1` within seconds of each other -
  a probe finishing at the moment a throttled download trips the threshold - and Oban's
  uniqueness answers `{:ok, <the other one>}` without inserting anything. The setting then
  says one time and the queues obey another.

  Measured on a real instance: the setting said 13:30 and the queues came back at 12:54,
  thirty-five minutes early, because the losing insert was the one that had just written
  the setting. The window opens after a restart, which clears the pause and leaves the
  queues running while a resume job is still in flight.

  So the newest decision wins outright: anything pending is cancelled, then the new job
  goes in. Cancelled rather than deleted, because a resume that was called off is
  something you want to be able to see.
  """

  use Oban.Worker,
    queue: :local_data,
    # One pending resume at a time. Without this every throttled download during a pause
    # would schedule another, and the queues would resume on whichever fired first.
    #
    # `:executing` is deliberately not here. This worker schedules its own successor when a
    # probe says the block is still on, and counting itself as a duplicate would make that
    # insert a silent no-op - leaving the queues stopped with nothing left to start them.
    unique: [period: :infinity, states: [:available, :scheduled]],
    tags: ["local_data"]

  import Ecto.Query, warn: false
  require Logger

  alias __MODULE__
  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.YoutubeStatus.Probe
  alias Pinchflat.Downloading.DownloadBackoff

  @doc """
  Schedules the resume for the moment the pause ends.

  Deliberately a scheduled job rather than a timer in a process: it survives a restart,
  and it is visible. A paused queue with nothing scheduled to lift it looks exactly like a
  queue that has silently stopped, which is the thing this whole area is about.

  Returns {:ok, %Oban.Job{}} | {:error, %Ecto.Changeset{}}
  """
  def schedule_for(%DateTime{} = until) do
    cancel_pending()

    Oban.insert(ResumeQueuesWorker.new(%{}, scheduled_at: until))
  end

  @doc """
  Calls off any resume that has not run yet.

  Written with `Repo` rather than `Oban.cancel_all_jobs/1` so that it also works during
  boot, before the job runner is up - which is where the other caller is. The startup
  reset of `executing` jobs next to it does the same.

  Returns integer()
  """
  def cancel_pending do
    {count, _} =
      Oban.Job
      |> where([j], j.worker == ^inspect(ResumeQueuesWorker) and j.state in ["available", "scheduled"])
      |> Repo.update_all(set: [state: "cancelled", cancelled_at: DateTime.utc_now()])

    count
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Settings.get!(:download_backoff_probe_enabled) do
      resume_if_answered()
    else
      DownloadBackoff.resume()
    end
  end

  # Resuming blind means the first thing that happens after a block that has not cleared is
  # another threshold's worth of refusals. Asking once costs one request and answers it.
  #
  # Anything other than a refusal resumes, including having nothing to ask about. Staying
  # stopped because the library is empty, or because the one video the probe picked was
  # deleted, is worse than resuming into a block that will simply pause again.
  defp resume_if_answered do
    if DownloadBackoff.resumable_queues() == [] do
      # Every queue this pause covers is also held by a switch. Asking YouTube whether the
      # block has cleared would be a request whose answer cannot change anything, and
      # during a block it would be the only traffic leaving this address. Stopping both
      # switches has to mean silence.
      Logger.info("Everything is stopped by hand: not probing, and lifting the backoff it would have lifted")

      DownloadBackoff.resume()
    else
      probe_and_decide()
    end
  end

  defp probe_and_decide do
    case Probe.run() do
      :ok ->
        Logger.info("YouTube answered: lifting the backoff early")
        DownloadBackoff.resume()

      :no_target ->
        DownloadBackoff.resume()

      {:error, message} ->
        Logger.warning("Probe was refused, staying paused: #{String.slice(message, 0, 200)}")
        DownloadBackoff.extend()

        :ok
    end
  end
end
