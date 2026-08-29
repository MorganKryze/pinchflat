defmodule Pinchflat.YtDlp.UpdateWorkerTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.YtDlp.UpdateWorker

  describe "perform/1" do
    test "calls the yt-dlp runner to update yt-dlp" do
      expect(YtDlpRunnerMock, :update, fn -> {:ok, ""} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, ""} end)

      perform_job(UpdateWorker, %{})
    end

    test "saves the new version to the database" do
      expect(YtDlpRunnerMock, :update, fn -> {:ok, ""} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      perform_job(UpdateWorker, %{})

      assert {:ok, "1.2.3"} = Settings.get(:yt_dlp_version)
    end

    test "records when the update was attempted" do
      expect(YtDlpRunnerMock, :update, fn -> {:ok, ""} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      perform_job(UpdateWorker, %{})

      assert {:ok, %DateTime{}} = Settings.get(:yt_dlp_last_update_attempted_at)
    end

    test "clears the last error when the update succeeds" do
      Settings.set(yt_dlp_last_update_error: "an old failure")

      expect(YtDlpRunnerMock, :update, fn -> {:ok, ""} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      perform_job(UpdateWorker, %{})

      assert {:ok, nil} = Settings.get(:yt_dlp_last_update_error)
    end

    test "fails the job when the update fails" do
      expect(YtDlpRunnerMock, :update, fn -> {:error, "could not reach the update server"} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      # The whole point of this worker's rewrite: an update that did not happen must not
      # be recorded by Oban as a job that succeeded.
      assert {:error, "could not reach the update server"} = perform_job(UpdateWorker, %{})
    end

    test "saves why the update failed" do
      expect(YtDlpRunnerMock, :update, fn -> {:error, "could not reach the update server"} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      perform_job(UpdateWorker, %{})

      assert {:ok, "could not reach the update server"} = Settings.get(:yt_dlp_last_update_error)
    end

    test "still records the current version when the update fails" do
      expect(YtDlpRunnerMock, :update, fn -> {:error, "nope"} end)
      expect(YtDlpRunnerMock, :version, fn -> {:ok, "1.2.3"} end)

      perform_job(UpdateWorker, %{})

      assert {:ok, "1.2.3"} = Settings.get(:yt_dlp_version)
    end
  end
end
