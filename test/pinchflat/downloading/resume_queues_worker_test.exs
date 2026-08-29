defmodule Pinchflat.Downloading.ResumeQueuesWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Downloading.DownloadBackoff
  alias Pinchflat.Downloading.ResumeQueuesWorker

  defp paused_until(minutes) do
    until = DateTime.utc_now() |> DateTime.add(minutes, :minute) |> DateTime.truncate(:second)
    Settings.set(download_backoff_paused_until: until)

    until
  end

  describe "perform/1 without the probe" do
    test "lifts the pause when the time is up" do
      paused_until(-1)

      assert :ok = perform_job(ResumeQueuesWorker, %{})
      assert DownloadBackoff.paused_until() == nil
    end
  end

  describe "perform/1 with the probe" do
    setup do
      Settings.set(download_backoff_probe_enabled: true)
      Settings.set(download_backoff_minutes: 30)

      :ok
    end

    test "lifts the pause when YouTube answers" do
      paused_until(-1)
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:ok, ~s({"live_status": "not_live"})}
      end)

      assert :ok = perform_job(ResumeQueuesWorker, %{})
      assert DownloadBackoff.paused_until() == nil
    end

    test "keeps the queues stopped when it is still being refused" do
      paused_until(-1)
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:error, "Sign in to confirm you're not a bot", 1}
      end)

      assert :ok = perform_job(ResumeQueuesWorker, %{})

      # Resuming blind would spend another threshold's worth of refusals discovering what
      # one request just said.
      assert DateTime.compare(DownloadBackoff.paused_until(), DateTime.utc_now()) == :gt
    end

    test "schedules the next attempt rather than leaving nothing to lift it" do
      paused_until(-1)
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:error, "Sign in to confirm you're not a bot", 1}
      end)

      assert :ok = perform_job(ResumeQueuesWorker, %{})

      # The worker schedules its own successor. If its uniqueness counted the running job
      # the insert would be a silent no-op and the queues would stay stopped for good.
      assert_enqueued(worker: ResumeQueuesWorker)
    end

    test "lifts the pause when there is nothing to ask about" do
      paused_until(-1)

      assert :ok = perform_job(ResumeQueuesWorker, %{})
      assert DownloadBackoff.paused_until() == nil
    end
  end
end
