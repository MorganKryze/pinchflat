defmodule Pinchflat.Downloading.ResumeQueuesWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :local_data,
    # One pending resume at a time. Without this every throttled download during a pause
    # would schedule another, and the queues would resume on whichever fired first.
    unique: [period: :infinity, states: [:available, :scheduled, :executing]],
    tags: ["local_data"]

  alias __MODULE__
  alias Pinchflat.Downloading.DownloadBackoff

  @doc """
  Schedules the resume for the moment the pause ends.

  Deliberately a scheduled job rather than a timer in a process: it survives a restart,
  and it is visible. A paused queue with nothing scheduled to lift it looks exactly like a
  queue that has silently stopped, which is the thing this whole area is about.

  Returns {:ok, %Oban.Job{}} | {:error, %Ecto.Changeset{}}
  """
  def schedule_for(%DateTime{} = until) do
    Oban.insert(ResumeQueuesWorker.new(%{}, scheduled_at: until))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    DownloadBackoff.resume()
  end
end
