defmodule Pinchflat.YoutubeStatus.SwitchesTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.YoutubeStatus.Switches
  alias Pinchflat.Downloading.DownloadBackoff

  describe "set/2 and paused?/1" do
    test "nothing is stopped to begin with" do
      refute Switches.paused?(:indexing)
      refute Switches.paused?(:downloading)
      refute Switches.any_paused?()
    end

    test "records the decision where a restart can find it" do
      Switches.set(:indexing, true)

      assert Switches.paused?(:indexing)
      # The setting is the record. Oban's own pause lives in memory and is gone by the
      # next boot, which is what this exists to survive.
      assert Settings.get!(:indexing_paused)
    end

    test "stops one half without touching the other" do
      Switches.set(:downloading, true)

      assert Switches.paused?(:downloading)
      refute Switches.paused?(:indexing)
    end

    test "starts it again" do
      Switches.set(:indexing, true)
      Switches.set(:indexing, false)

      refute Switches.paused?(:indexing)
    end
  end

  describe "paused_queues/0" do
    test "is empty while nothing is stopped" do
      assert Switches.paused_queues() == []
    end

    test "names both indexing queues" do
      Switches.set(:indexing, true)

      assert Enum.sort(Switches.paused_queues()) == [:fast_indexing, :media_collection_indexing]
    end
  end

  describe "apply_stored/0" do
    test "runs whether or not anything is stopped" do
      assert :ok = Switches.apply_stored()

      Switches.set(:downloading, true)
      assert :ok = Switches.apply_stored()
    end
  end

  describe "the backoff and the switches together" do
    test "a resume leaves a queue somebody stopped on purpose alone" do
      Switches.set(:downloading, true)

      # The backoff stops four queues and this one is not its to restart. Resuming the lot
      # when the block cleared would quietly undo the decision.
      refute :media_fetching in DownloadBackoff.resumable_queues()
      assert :fast_indexing in DownloadBackoff.resumable_queues()
    end

    test "it resumes everything when no switch is off" do
      assert Enum.sort(DownloadBackoff.resumable_queues()) == Enum.sort(DownloadBackoff.yt_dlp_queues())
    end
  end
end
