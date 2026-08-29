defmodule Pinchflat.Downloading.DownloadBackoffTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Downloading.DownloadBackoff
  alias Pinchflat.Downloading.ResumeQueuesWorker

  # The message as yt-dlp writes it, apostrophe and all, rather than the pattern we match
  # it with. A fixture built from our own constant cannot tell us whether the constant is
  # right, which is how this arming was broken in production while every test passed.
  @real_throttle "ERROR: [youtube] abc: Sign in to confirm you\u2019re not a bot. Use --cookies-from-browser"

  defp throttled(minutes_ago) do
    media_item_fixture(%{
      media_filepath: nil,
      last_error: @real_throttle,
      last_error_at: DateTime.utc_now() |> DateTime.add(-minutes_ago, :minute) |> DateTime.truncate(:second)
    })
  end

  setup do
    Settings.set(download_backoff_enabled: true)
    Settings.set(download_backoff_threshold: 3)
    Settings.set(download_backoff_minutes: 30)

    :ok
  end

  describe "maybe_pause/0" do
    test "does nothing when the feature is off" do
      Settings.set(download_backoff_enabled: false)
      for _ <- 1..5, do: throttled(1)

      assert :ok = DownloadBackoff.maybe_pause()
      assert DownloadBackoff.paused_until() == nil
    end

    test "does nothing below the threshold" do
      for _ <- 1..2, do: throttled(1)

      assert :ok = DownloadBackoff.maybe_pause()
      assert DownloadBackoff.paused_until() == nil
    end

    test "pauses once enough refusals have piled up with nothing getting through" do
      for _ <- 1..3, do: throttled(1)

      assert {:paused, %DateTime{}} = DownloadBackoff.maybe_pause()
      assert DownloadBackoff.paused_until()
    end

    test "scatters the pause instead of ending it on the same offset every time" do
      Settings.set(download_backoff_minutes: 60)

      lengths =
        Enum.map(1..12, fn _ ->
          Settings.set(download_backoff_paused_until: nil)
          for _ <- 1..3, do: throttled(1)

          {:paused, until} = DownloadBackoff.maybe_pause()
          DateTime.diff(until, DateTime.utc_now())
        end)

      # During a block the probe at the end of each pause is the only traffic leaving this
      # address, so a run of pauses exactly an hour apart is the easiest thing there is to
      # recognise. A fifth either way, and never the same twice.
      assert Enum.uniq(lengths) != [3600]
      assert Enum.min(lengths) >= 2880
      assert Enum.max(lengths) <= 4320
    end

    test "does not pause if anything is still succeeding" do
      for _ <- 1..5, do: throttled(1)
      media_item_fixture(%{media_downloaded_at: DateTime.utc_now()})

      # A throttle that lets some downloads through is not a block, and stopping
      # everything would cost more than it saves.
      assert :ok = DownloadBackoff.maybe_pause()
      assert DownloadBackoff.paused_until() == nil
    end

    test "ignores refusals older than the window" do
      for _ <- 1..5, do: throttled(90)

      assert :ok = DownloadBackoff.maybe_pause()
    end

    test "schedules the resume for the moment the pause ends" do
      for _ <- 1..3, do: throttled(1)

      {:paused, until} = DownloadBackoff.maybe_pause()

      # A scheduled job rather than a timer in a process: it survives a restart, and a
      # paused queue with nothing visible to lift it looks like one that silently stopped.
      assert [job] = all_enqueued(worker: ResumeQueuesWorker)
      assert DateTime.compare(job.scheduled_at, until) == :eq
    end

    test "does not stack pauses while one is running" do
      for _ <- 1..3, do: throttled(1)
      {:paused, until} = DownloadBackoff.maybe_pause()

      assert :ok = DownloadBackoff.maybe_pause()
      assert [_only_one] = all_enqueued(worker: ResumeQueuesWorker)
      assert DateTime.compare(DownloadBackoff.paused_until(), until) == :eq
    end

    test "can pause again once the previous pause has expired" do
      for _ <- 1..3, do: throttled(1)

      Settings.set(
        download_backoff_paused_until: DateTime.utc_now() |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)
      )

      # If the block outlasts the pause, tripping again is how it keeps waiting - no
      # growing curve, no state, same behaviour every time.
      assert {:paused, _until} = DownloadBackoff.maybe_pause()
    end
  end

  describe "extend/0" do
    setup do
      Settings.set(download_backoff_minutes: 30)
      :ok
    end

    defp pause_minutes do
      trunc(DateTime.diff(DownloadBackoff.paused_until(), DateTime.utc_now()) / 60)
    end

    test "each refused probe waits longer than the last, up to four bases" do
      # The first pause is one base; these are the ones after it, so the run starts at two.
      for expected <- [60, 90, 120, 120, 120] do
        DownloadBackoff.extend()

        # A fifth of jitter either way, so the assertion is on the band rather than the
        # number. Thirteen hours of block costs eight requests this way instead of
        # twenty-six, and the rate decays rather than holding steady.
        assert_in_delta pause_minutes(), expected, expected * 0.2 + 1
      end
    end

    test "a probe that answers puts it back to the start" do
      for _ <- 1..3, do: DownloadBackoff.extend()
      DownloadBackoff.resume()

      assert Settings.get!(:download_backoff_extensions) == 0

      # Back to one step above the base rather than carrying on from the ceiling.
      DownloadBackoff.extend()
      assert_in_delta pause_minutes(), 60, 13
    end

    test "keeps the interval fixed when the escalation is off" do
      Settings.set(download_backoff_escalate: false)

      for _ <- 1..4, do: DownloadBackoff.extend()

      assert_in_delta pause_minutes(), 30, 7
    end
  end

  describe "resume/0" do
    test "clears the pause" do
      for _ <- 1..3, do: throttled(1)
      DownloadBackoff.maybe_pause()

      assert :ok = DownloadBackoff.resume()
      assert DownloadBackoff.paused_until() == nil
    end

    test "is safe when nothing is paused" do
      # A restart clears the pause while the scheduled resume survives, so this runs on
      # unpaused queues as a matter of course.
      assert :ok = DownloadBackoff.resume()
    end
  end

  describe "yt_dlp_queues/0" do
    test "covers every queue that reaches youtube" do
      # Pausing only media_fetching would leave indexing and metadata calling out on the
      # same blocked address, which is the easiest version of this to get wrong.
      assert Enum.sort(DownloadBackoff.yt_dlp_queues()) ==
               Enum.sort(~w(media_fetching fast_indexing media_collection_indexing remote_metadata)a)
    end
  end
end
