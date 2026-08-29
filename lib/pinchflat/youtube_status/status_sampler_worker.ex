defmodule Pinchflat.YoutubeStatus.StatusSamplerWorker do
  @moduledoc """
  Writes down how the connection to YouTube behaved since the last time it looked.

  On a cron rather than triggered by a download, because the readings that matter most are
  the ones where nothing happened: a queue that has gone quiet leaves no event to hang a
  measurement on.
  """

  use Oban.Worker,
    queue: :local_data,
    # A sample is worth nothing once the next one is due, so a backlog would only write
    # windows that have already been covered.
    unique: [period: :infinity, states: [:available, :scheduled, :executing]],
    tags: ["local_data"]

  alias Pinchflat.YoutubeStatus

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _sample} = YoutubeStatus.sample!()
    YoutubeStatus.prune!()

    :ok
  end
end
