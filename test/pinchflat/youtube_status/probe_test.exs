defmodule Pinchflat.YoutubeStatus.ProbeTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.YoutubeStatus.Probe

  describe "run/0" do
    test "says so when there is nothing to ask about" do
      # An empty library is not a block, and staying stopped over one would be the worst
      # kind of stuck.
      assert Probe.run() == :no_target
    end

    test "asks about a video that has already downloaded" do
      media_item = media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})
      _pending = media_item_fixture(%{media_filepath: nil, media_downloaded_at: nil})

      expect(YtDlpRunnerMock, :run, fn url, :get_downloadable_status, _opts, _ot, _addl ->
        assert url == media_item.original_url

        {:ok, ~s({"live_status": "not_live"})}
      end)

      assert Probe.run() == :ok
    end

    test "falls back to any media item when nothing has downloaded yet" do
      media_item = media_item_fixture(%{media_filepath: nil, media_downloaded_at: nil})

      expect(YtDlpRunnerMock, :run, fn url, :get_downloadable_status, _opts, _ot, _addl ->
        assert url == media_item.original_url

        {:ok, ~s({"live_status": "not_live"})}
      end)

      assert Probe.run() == :ok
    end

    test "reports a refusal of the address" do
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:error, "Sign in to confirm you're not a bot", 1}
      end)

      assert {:error, message} = Probe.run()
      assert message =~ "not a bot"
    end

    test "counts a message nobody recognises as a refusal" do
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      # This is the one the pre-download check produced while the address was refused.
      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:error, "No title found in player response", 1}
      end)

      assert {:error, _message} = Probe.run()
    end

    test "treats a verdict on the video as no answer at all" do
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now() |> DateTime.truncate(:second)})

      # The video is gone. That says nothing about the address, and extending the pause
      # over it would hold the queues shut for good.
      expect(YtDlpRunnerMock, :run, fn _url, :get_downloadable_status, _opts, _ot, _addl ->
        {:error, "Video unavailable", 1}
      end)

      assert Probe.run() == :no_target
    end
  end
end
