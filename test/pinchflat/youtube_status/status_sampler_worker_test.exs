defmodule Pinchflat.YoutubeStatus.StatusSamplerWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.YoutubeStatus
  alias Pinchflat.YoutubeStatus.StatusSample
  alias Pinchflat.YoutubeStatus.StatusSamplerWorker

  describe "perform/1" do
    test "records one reading of the window that just passed" do
      # A few seconds back rather than this instant: the window ends at the moment the
      # sample is taken, so "now" sits on the boundary and belongs to the next one.
      downloaded_at = DateTime.utc_now() |> DateTime.add(-5, :second) |> DateTime.truncate(:second)
      media_item_fixture(%{media_downloaded_at: downloaded_at})

      assert :ok = perform_job(StatusSamplerWorker, %{})

      assert %StatusSample{state: :nominal, downloads: 1} = YoutubeStatus.latest_sample()
    end

    test "drops readings past the retention window as it goes" do
      Repo.insert!(%StatusSample{
        state: :idle,
        window_seconds: 300,
        inserted_at: DateTime.utc_now() |> DateTime.add(-45, :day) |> DateTime.truncate(:second)
      })

      assert :ok = perform_job(StatusSamplerWorker, %{})

      # The old one is gone, the one just taken is not.
      assert Repo.aggregate(StatusSample, :count) == 1
    end
  end
end
