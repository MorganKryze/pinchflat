defmodule Pinchflat.Downloading.ResumeQueuesWorkerTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings
  alias Pinchflat.YoutubeStatus.Switches
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

    test "asks nothing while everything is stopped by hand" do
      paused_until(-1)
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      Switches.set(:indexing, true)
      Switches.set(:downloading, true)

      # No expectation on the runner: a probe here would be a request whose answer cannot
      # change anything, and during a block it would be the only traffic leaving this
      # address. Stopping both switches has to mean silence.
      assert :ok = perform_job(ResumeQueuesWorker, %{})
      assert DownloadBackoff.paused_until() == nil
    end

    test "lifts the pause when there is nothing to ask about" do
      paused_until(-1)

      assert :ok = perform_job(ResumeQueuesWorker, %{})
      assert DownloadBackoff.paused_until() == nil
    end
  end

  describe "schedule_for/1" do
    defp pending_resumes do
      Oban.Job
      |> where([j], j.worker == ^inspect(ResumeQueuesWorker) and j.state in ["available", "scheduled"])
      |> Repo.all()
    end

    test "the newest decision wins outright" do
      early = DateTime.utc_now() |> DateTime.add(35, :minute) |> DateTime.truncate(:second)
      late = DateTime.utc_now() |> DateTime.add(70, :minute) |> DateTime.truncate(:second)

      {:ok, _first} = ResumeQueuesWorker.schedule_for(early)
      {:ok, _second} = ResumeQueuesWorker.schedule_for(late)

      # Oban's uniqueness answers {:ok, <the other one>} without inserting, so on a real
      # instance the setting said 13:30 and the queues came back at 12:54 - the losing
      # insert was the one that had just written the setting.
      assert [job] = pending_resumes()
      assert DateTime.compare(job.scheduled_at, late) == :eq
    end

    test "the setting and the queue agree after an extension" do
      Settings.set(download_backoff_minutes: 30)
      Settings.set(download_backoff_escalate: true)

      DownloadBackoff.extend()
      DownloadBackoff.extend()

      assert [job] = pending_resumes()
      assert_in_delta DateTime.diff(job.scheduled_at, DownloadBackoff.paused_until()), 0, 1
    end

    test "a resume called off is visible rather than gone" do
      ResumeQueuesWorker.schedule_for(DateTime.utc_now() |> DateTime.add(10, :minute))
      ResumeQueuesWorker.schedule_for(DateTime.utc_now() |> DateTime.add(20, :minute))

      cancelled = Oban.Job |> where([j], j.state == "cancelled") |> Repo.all()

      assert length(cancelled) == 1
      assert hd(cancelled).cancelled_at
    end
  end
end
