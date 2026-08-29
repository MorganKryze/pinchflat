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

  ## What is not covered

  `remote_metadata` keeps running. It refreshes a source's own details rather than listing
  or fetching media, and neither switch claims to stop it. The automatic backoff does stop
  it, because that one is about not touching a refused address at all.
  """

  require Logger

  alias Pinchflat.Settings

  @switches %{
    indexing: %{setting: :indexing_paused, queues: ~w(fast_indexing media_collection_indexing)a},
    downloading: %{setting: :downloading_paused, queues: ~w(media_fetching)a}
  }

  @doc """
  The switches there are.

  Returns [atom()]
  """
  def names, do: Map.keys(@switches)

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

  Returns :ok
  """
  def apply_stored do
    Enum.each(names(), fn switch ->
      if paused?(switch) do
        Logger.info("Re-applying the #{switch} pause after a restart")
        apply_to_queues(@switches[switch].queues, true)
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
end
