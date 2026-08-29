defmodule Pinchflat.Downloading.DownloadHealthTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Tasks
  alias Pinchflat.Settings
  alias Pinchflat.Downloading.DownloadHealth
  alias Pinchflat.Downloading.MediaDownloadWorker

  defp hours_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :hour) |> DateTime.truncate(:second)

  describe "downloads_since/1" do
    test "counts only what finished inside the window" do
      media_item_fixture(%{media_downloaded_at: hours_ago(0)})
      media_item_fixture(%{media_downloaded_at: hours_ago(5)})

      assert DownloadHealth.downloads_since(hours_ago(1)) == 1
    end
  end

  describe "failures_since/1" do
    test "counts only what failed inside the window" do
      media_item_fixture(%{last_error: "nope", last_error_at: hours_ago(0)})
      media_item_fixture(%{last_error: "nope", last_error_at: hours_ago(5)})

      assert DownloadHealth.failures_since(hours_ago(1)) == 1
    end

    test "counts the throttle yt-dlp actually writes" do
      # The apostrophe is U+2019, as it comes out of yt-dlp. This count is matched in SQL,
      # where the normalising in `DownloadErrors.find/1` is not available, so the pattern
      # has to be something SQLite can find on its own. It was not: on a real instance
      # this returned 0 while fifty-four throttles sat in the table, and the queue backoff
      # never reached its threshold.
      media_item_fixture(%{
        last_error: "ERROR: [youtube] abc: Sign in to confirm you\u2019re not a bot. Use --cookies",
        last_error_at: hours_ago(0)
      })

      assert DownloadHealth.throttle_failures_since(hours_ago(1)) == 1
    end

    test "separates a throttle from every other failure" do
      media_item_fixture(%{last_error: "Sign in to confirm you're not a bot", last_error_at: hours_ago(0)})
      media_item_fixture(%{last_error: "Video unavailable", last_error_at: hours_ago(0)})

      # The distinction is the whole reason this number exists: a throttle means stop
      # asking, everything else is worth another attempt straight away.
      assert DownloadHealth.failures_since(hours_ago(1)) == 2
      assert DownloadHealth.throttle_failures_since(hours_ago(1)) == 1
    end
  end

  describe "last_successful_download_at/0" do
    test "is nil when nothing has ever downloaded" do
      media_item_fixture(%{media_filepath: nil, media_downloaded_at: nil})

      assert DownloadHealth.last_successful_download_at() == nil
    end

    test "is the most recent success" do
      media_item_fixture(%{media_downloaded_at: hours_ago(5)})
      recent = hours_ago(1)
      media_item_fixture(%{media_downloaded_at: recent})

      assert DateTime.compare(DownloadHealth.last_successful_download_at(), recent) == :eq
    end
  end

  describe "pending_without_job_count/0" do
    test "counts a pending media item that nothing is going to download" do
      media_item_fixture(%{media_filepath: nil})

      # This is the hole the fork exists for: an item that should download, with no job
      # anywhere that will ever do it, and nothing saying so.
      assert DownloadHealth.pending_without_job_count() == 1
    end

    test "does not count one that has a job waiting" do
      media_item = media_item_fixture(%{media_filepath: nil})
      {:ok, _task} = MediaDownloadWorker.kickoff_with_task(media_item)

      assert DownloadHealth.pending_without_job_count() == 0
    end

    test "counts it again once that job is gone" do
      media_item = media_item_fixture(%{media_filepath: nil})
      {:ok, _task} = MediaDownloadWorker.kickoff_with_task(media_item)
      Tasks.delete_pending_tasks_for(media_item)

      assert DownloadHealth.pending_without_job_count() == 1
    end

    test "ignores media items that are already downloaded" do
      media_item_fixture(%{media_downloaded_at: hours_ago(1)})

      assert DownloadHealth.pending_without_job_count() == 0
    end
  end

  describe "set_aside_without_reason_count/0" do
    test "counts a media item set aside with nothing saying why" do
      media_item_fixture(%{prevent_download: true, blocked_reason: nil})

      assert DownloadHealth.set_aside_without_reason_count() == 1
    end

    test "does not count one that recorded a reason" do
      media_item_fixture(%{prevent_download: true, blocked_reason: "Blocked by a user script (exit code 3)"})

      assert DownloadHealth.set_aside_without_reason_count() == 0
    end
  end

  describe "summary/1" do
    test "reports the yt-dlp update state alongside the counts" do
      Settings.set(yt_dlp_version: "2026.8.19")
      Settings.set(yt_dlp_last_update_error: "HTTP Error 403: Forbidden")

      summary = DownloadHealth.summary()

      assert summary.yt_dlp_version == "2026.8.19"
      assert summary.yt_dlp_last_update_error == "HTTP Error 403: Forbidden"
      assert summary.window_hours == 1
    end
  end
end
