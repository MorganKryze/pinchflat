defmodule Pinchflat.YoutubeStatus.Switches do
  @moduledoc """
  Stopping indexing or downloading by hand, and keeping it stopped.

  Two switches, not one. On a refused address indexing carried on working while every
  download was turned away, so an operator waiting for a block to clear has a reason to
  leave one running and stop the other. Wiring them together would throw away the half
  that still works.

  ## Why the setting exists as well as the pause

  `Oban.pause_queue/1` lives in memory. A restart brings the queues back running with
  nothing to say they were ever stopped, which has already caused one silent failure in
  this codebase. The setting is the record; the pause is its effect, re-applied on boot.

  ## Radio silence

  Stopping both stops every queue that reaches YouTube, and the backoff's probe with them:
  there is nothing left for it to start, so asking whether the block has cleared would be
  a request whose answer cannot change anything.

  That is the reason `remote_metadata` sits under indexing rather than outside both. It
  refreshes a source's own details rather than listing or fetching media, so on its own it
  belongs to neither - but leaving it out meant an operator who had stopped everything was
  still talking to YouTube, and "stopped everything" has to mean it.
  """

  require Logger

  alias Pinchflat.Settings

  @switches %{
    indexing: %{setting: :indexing_paused, queues: ~w(fast_indexing media_collection_indexing remote_metadata)a},
    downloading: %{setting: :downloading_paused, queues: ~w(media_fetching)a}
  }

  @doc """
  The switches there are, in the order work happens: a video is indexed before it is
  downloaded, so that is the order they are read and shown in.

  Returns [atom()]
  """
  def names, do: [:indexing, :downloading]

  @doc """
  Whether a switch is on.

  Returns boolean()
  """
  def paused?(switch), do: Settings.get!(@switches[switch].setting)

  @doc """
  Whether anything is stopped by hand.

  Returns boolean()
  """
  def any_paused?, do: Enum.any?(names(), &paused?/1)

  @doc """
  Stops or restarts one half of the work and records which it is.

  Returns :ok
  """
  def set(switch, paused?) when is_map_key(@switches, switch) and is_boolean(paused?) do
    %{setting: setting, queues: queues} = @switches[switch]

    Settings.set([{setting, paused?}])
    apply_to_queues(queues, paused?)

    Logger.info("#{switch} #{if paused?, do: "paused", else: "resumed"} by hand")

    :ok
  end

  @doc """
  Puts the queues back the way the switches say they should be.

  Called after the job runner starts, because a restart wipes Oban's pauses and the
  operator's decision should outlive a container.

  Confirmed rather than assumed. A pause is a broadcast, and a producer that has not
  finished subscribing when it goes out never hears it - which would leave a queue
  somebody stopped quietly running, with the setting still claiming otherwise. That is the
  exact shape of the bug this fork exists to fix, so it is checked rather than hoped for.

  Returns :ok
  """
  def apply_stored do
    Enum.each(names(), fn switch ->
      if paused?(switch) do
        Logger.info("Re-applying the #{switch} pause after a restart")

        Enum.each(@switches[switch].queues, &pause_and_confirm/1)
      end
    end)
  end

  @doc """
  Queues that must stay stopped whatever else happens.

  The automatic backoff resumes everything it stopped, and it stops more than these. Told
  to resume, it would quietly undo a decision somebody made deliberately.

  Returns [atom()]
  """
  def paused_queues do
    Enum.flat_map(names(), fn switch ->
      if paused?(switch), do: @switches[switch].queues, else: []
    end)
  end

  defp apply_to_queues(queues, true), do: Enum.each(queues, &Oban.pause_queue(queue: &1))
  defp apply_to_queues(queues, false), do: Enum.each(queues, &Oban.resume_queue(queue: &1))

  # Twenty tries, twenty milliseconds apart. It lands first time whenever the producer is
  # already listening, which is nearly always; the rest is there for the boot where it is
  # not.
  @confirm_attempts 20
  @confirm_wait_ms 20

  defp pause_and_confirm(queue) do
    Oban.pause_queue(queue: queue)

    # Nothing to confirm against when no queues are running at all, which is how the test
    # environment is set up.
    if queue_configured?(queue), do: confirm_paused(queue, @confirm_attempts), else: :ok
  end

  defp confirm_paused(queue, 0) do
    Logger.error("Could not confirm that the #{queue} queue is paused - it may be running")
  end

  defp confirm_paused(queue, attempts) do
    case queue_state(queue) do
      %{paused: true} ->
        :ok

      _ ->
        Process.sleep(@confirm_wait_ms)
        Oban.pause_queue(queue: queue)
        confirm_paused(queue, attempts - 1)
    end
  end

  defp queue_configured?(queue) do
    Keyword.has_key?(Oban.config().queues, queue)
  rescue
    _ -> false
  end

  defp queue_state(queue) do
    Oban.check_queue(queue: queue)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
