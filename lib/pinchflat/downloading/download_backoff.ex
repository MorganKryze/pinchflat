defmodule Pinchflat.Downloading.DownloadBackoff do
  @moduledoc """
  Stops asking YouTube for things while YouTube is refusing to answer.

  A throttled request fails fast - there is no download, just a refusal - so nothing slows
  down on its own during a block. The queue is consumed at full speed for nothing, and
  every wasted request keeps the block alive.

  Off unless `download_backoff_enabled` is set. It is the only thing in this fork that
  stops work by itself, so it is opted into rather than inherited.

  ## Why there is no polling loop

  The moment worth reacting to is a download failing with a throttle, and that is already
  a place where code is running. So the check happens there, and the resume is an Oban job
  scheduled for the exact moment the pause ends. Nothing wakes up every minute to ask
  whether anything has changed, and the scheduled job is visible in the dashboard, which
  is the difference between a system that pauses and a system that has gone quiet.

  ## Why the resume is not a probe

  Waiting the pause out is the whole behaviour. Testing the water with a request to
  YouTube would add traffic during a block, which is what this exists to stop, and would
  make when-it-resumes depend on something nobody can see. If the block outlasts the
  pause, the next failure trips the threshold again and it pauses again - same effect, no
  hidden state.
  """

  require Logger

  alias Pinchflat.Settings
  alias Pinchflat.Downloading.DownloadHealth
  alias Pinchflat.Downloading.ResumeQueuesWorker
  alias Pinchflat.YoutubeStatus.Switches

  # Every queue that reaches YouTube through yt-dlp. Pausing only `media_fetching` would
  # leave indexing and metadata still calling out on the same blocked address, which is
  # the mistake this is easiest to make.
  @yt_dlp_queues ~w(media_fetching fast_indexing media_collection_indexing remote_metadata)a

  @doc """
  Called when a download fails with a throttle. Pauses the yt-dlp queues if enough of them
  have failed recently and nothing at all has succeeded.

  Returns :ok | {:paused, %DateTime{}}
  """
  def maybe_pause do
    if Settings.get!(:download_backoff_enabled) && !currently_paused?() && threshold_met?() do
      pause()
    else
      :ok
    end
  end

  @doc """
  Lifts the pause. Safe to call on queues that are not paused - resuming an unpaused queue
  does nothing, which matters because a restart clears the pause while the scheduled
  resume job survives.

  Returns :ok
  """
  def resume do
    Enum.each(resumable_queues(), &Oban.resume_queue(queue: &1))
    Settings.set(download_backoff_paused_until: nil)
    Logger.info("Download backoff lifted, yt-dlp queues resumed")

    :ok
  end

  @doc """
  Keeps the queues stopped for another window.

  Used when a probe says YouTube is still refusing. Re-applies the pause rather than only
  moving the date, because a restart clears Oban's pauses while the scheduled resume
  survives - so this can run against queues that came back up.

  Returns {:paused, %DateTime{}}
  """
  def extend do
    Logger.warning("Still being refused: keeping the yt-dlp queues stopped")

    pause()
  end

  @doc """
  When the current pause ends, or nil if there is not one.

  Returns %DateTime{} | nil
  """
  def paused_until do
    Settings.get!(:download_backoff_paused_until)
  end

  @doc """
  The queues this pauses. Public so the health summary can say what is affected without
  keeping its own copy of the list.

  Returns [atom()]
  """
  def yt_dlp_queues, do: @yt_dlp_queues

  @doc """
  The queues a resume will actually restart: everything except what somebody stopped on
  purpose.

  This pauses more queues than the manual switches cover, so resuming the lot when the
  block clears would silently undo a decision that has nothing to do with the block.

  Returns [atom()]
  """
  def resumable_queues do
    held = Switches.paused_queues()

    Enum.reject(@yt_dlp_queues, &(&1 in held))
  end

  defp currently_paused? do
    case paused_until() do
      nil -> false
      until -> DateTime.compare(until, DateTime.utc_now()) == :gt
    end
  end

  # The window and the pause are the same length on purpose: "if the last thirty minutes
  # were nothing but refusals, stop for thirty minutes" is one number to reason about
  # instead of two that have to be kept consistent with each other. The pause is then
  # scattered around it - see `jittered_seconds/1`.
  defp threshold_met? do
    minutes = Settings.get!(:download_backoff_minutes)
    since = DateTime.add(DateTime.utc_now(), -minutes, :minute)

    DownloadHealth.throttle_failures_since(since) >= Settings.get!(:download_backoff_threshold) &&
      DownloadHealth.downloads_since(since) == 0
  end

  defp pause do
    minutes = Settings.get!(:download_backoff_minutes)
    until = DateTime.utc_now() |> DateTime.add(jittered_seconds(minutes), :second) |> DateTime.truncate(:second)

    Enum.each(@yt_dlp_queues, &Oban.pause_queue(queue: &1))
    Settings.set(download_backoff_paused_until: until)
    ResumeQueuesWorker.schedule_for(until)

    Logger.warning("Throttled by YouTube: pausing yt-dlp queues until #{until}")

    {:paused, until}
  end

  # A fifth either way, so a pause never ends on the same offset twice.
  #
  # Nothing depends on the exact minute, and a run of pauses that end exactly thirty
  # minutes apart is the cheapest thing in the world to recognise. It matters more here
  # than anywhere else in this codebase: during a block the probe at the end of each pause
  # is the only traffic leaving this address, so there is nothing for its regularity to
  # hide in. The retry backoff already scatters itself for the same reason.
  #
  # This removes a tell. It does not make anything look human, and a request every half
  # hour from an otherwise silent address is still a request every half hour.
  defp jittered_seconds(minutes) do
    trunc(minutes * 60 * (0.8 + :rand.uniform() * 0.4))
  end
end
