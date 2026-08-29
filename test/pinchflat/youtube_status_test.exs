defmodule Pinchflat.YoutubeStatusTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.YoutubeStatus
  alias Pinchflat.YoutubeStatus.Switches
  alias Pinchflat.YoutubeStatus.StatusSample

  @throttle "ERROR: [youtube] abc: Sign in to confirm you're not a bot. Use --cookies"
  @collection_worker "Pinchflat.SlowIndexing.MediaCollectionIndexingWorker"

  defp minutes_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :minute) |> DateTime.truncate(:second)
  # Oban keeps its timestamps to the microsecond and refuses anything coarser.
  defp usec_minutes_ago(n), do: DateTime.add(DateTime.utc_now(), -n, :minute)

  # Inserted as a struct because `inserted_at` is when the reading was taken, which the
  # changeset has no business accepting from outside.
  defp sample_at(inserted_at, state \\ :idle) do
    Repo.insert!(%StatusSample{state: state, window_seconds: 300, inserted_at: inserted_at})
  end

  defp indexing_job(attrs) do
    Repo.insert!(
      struct(
        %Oban.Job{
          worker: @collection_worker,
          queue: "media_collection_indexing",
          args: %{},
          attempt: 1,
          max_attempts: 3,
          scheduled_at: DateTime.utc_now()
        },
        attrs
      )
    )
  end

  describe "measure/2" do
    test "counts downloads that finished inside the window" do
      media_item_fixture(%{media_downloaded_at: minutes_ago(2)})
      media_item_fixture(%{media_downloaded_at: minutes_ago(30)})

      assert %{downloads: 1} = YoutubeStatus.measure(minutes_ago(5), DateTime.utc_now())
    end

    test "tells a refused address apart from a verdict on one video" do
      media_item_fixture(%{last_error: @throttle, last_error_at: minutes_ago(1)})
      media_item_fixture(%{last_error: "No title found in player response", last_error_at: minutes_ago(1)})
      media_item_fixture(%{last_error: "Video unavailable", last_error_at: minutes_ago(1)})

      counts = YoutubeStatus.measure(minutes_ago(5), DateTime.utc_now())

      # An unrecognised message counts as a possible block: that is exactly what the
      # pre-download check produced while the address was refused.
      assert counts.download_failures == 3
      assert counts.connection_failures == 2
      assert counts.throttle_failures == 1
    end

    test "counts indexing from the jobs it already leaves behind" do
      indexing_job(%{state: "completed", completed_at: usec_minutes_ago(1)})
      indexing_job(%{state: "retryable", attempted_at: usec_minutes_ago(1)})
      indexing_job(%{state: "discarded", attempted_at: usec_minutes_ago(1)})
      indexing_job(%{state: "completed", completed_at: usec_minutes_ago(30)})

      counts = YoutubeStatus.measure(minutes_ago(5), DateTime.utc_now())

      assert counts.indexing_successes == 1
      assert counts.indexing_failures == 2
    end

    test "ignores workers that do not talk to YouTube" do
      Repo.insert!(%Oban.Job{
        worker: "Pinchflat.Downloading.MediaRetentionWorker",
        queue: "local_data",
        args: %{},
        state: "completed",
        completed_at: usec_minutes_ago(1),
        scheduled_at: DateTime.utc_now()
      })

      assert %{indexing_successes: 0} = YoutubeStatus.measure(minutes_ago(5), DateTime.utc_now())
    end
  end

  describe "state_for/1" do
    defp counts(overrides) do
      Map.merge(
        %{
          downloads: 0,
          download_failures: 0,
          connection_failures: 0,
          throttle_failures: 0,
          indexing_successes: 0,
          indexing_failures: 0
        },
        overrides
      )
    end

    test "green needs a download that got through" do
      assert YoutubeStatus.state_for(counts(%{downloads: 1})) == :nominal
    end

    test "green survives failures alongside the successes" do
      # Something is getting through, which is what the colour is about. A library with a
      # few private videos in it would otherwise never read green.
      assert YoutubeStatus.state_for(counts(%{downloads: 5, connection_failures: 2})) == :nominal
    end

    test "orange when indexing answers and nothing comes down" do
      assert YoutubeStatus.state_for(counts(%{connection_failures: 3, indexing_successes: 1})) == :degraded
    end

    test "red only when both tiers are refusing" do
      assert YoutubeStatus.state_for(counts(%{connection_failures: 3, indexing_failures: 1})) == :blocked
    end

    test "orange rather than red when indexing is still working somewhere" do
      # One source failing to index while others succeed is a bad URL, not a block.
      assert YoutubeStatus.state_for(counts(%{connection_failures: 3, indexing_failures: 1, indexing_successes: 2})) ==
               :degraded
    end

    test "grey when nothing was attempted" do
      assert YoutubeStatus.state_for(counts(%{})) == :idle
    end

    test "grey when the only failures are verdicts on single videos" do
      # Five private videos say nothing about the connection.
      assert YoutubeStatus.state_for(counts(%{download_failures: 5})) == :idle
    end
  end

  describe "sample!/1" do
    test "writes a reading with the counts that produced it" do
      media_item_fixture(%{media_downloaded_at: minutes_ago(1)})

      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.state == :nominal
      assert sample.downloads == 1
      assert sample.window_seconds == YoutubeStatus.interval_seconds()
    end

    test "covers the gap since the previous sample rather than a fixed window" do
      sample_at(minutes_ago(20))

      {:ok, sample} = YoutubeStatus.sample!()

      # A run that was missed widens the next window instead of losing the time.
      assert_in_delta sample.window_seconds, 20 * 60, 5
    end

    test "counts a failure that happened between two samples" do
      sample_at(minutes_ago(10))

      media_item_fixture(%{last_error: @throttle, last_error_at: minutes_ago(7)})

      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.state == :degraded
      assert sample.throttle_failures == 1
    end

    test "does not blame one window for a fortnight of downtime" do
      sample_at(minutes_ago(60 * 24 * 14))

      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.window_seconds == 3600
    end
  end

  describe "the disabled reading" do
    test "explains quiet that somebody asked for" do
      Switches.set(:downloading, true)

      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.state == :disabled
      assert YoutubeStatus.current().state == :disabled
    end

    test "does not overrule evidence" do
      Switches.set(:indexing, true)
      media_item_fixture(%{last_error: @throttle, last_error_at: minutes_ago(2)})

      # Indexing was stopped by hand and downloading was not, so a refused download is
      # still a refused download. Painting it blue would hide a real block behind a switch
      # that has nothing to do with it.
      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.state == :degraded
    end

    test "goes back to grey once the switch is off" do
      Switches.set(:downloading, true)
      Switches.set(:downloading, false)

      {:ok, sample} = YoutubeStatus.sample!()

      assert sample.state == :idle
    end
  end

  describe "history/1 and latest_sample/0" do
    test "reads oldest first and answers with the newest" do
      for minutes <- [30, 10, 90], do: sample_at(minutes_ago(minutes))

      history = YoutubeStatus.history(1)

      assert length(history) == 2
      assert [older, newer] = history
      assert DateTime.compare(older.inserted_at, newer.inserted_at) == :lt
      assert DateTime.compare(YoutubeStatus.latest_sample().inserted_at, newer.inserted_at) == :eq
    end
  end

  describe "current/1" do
    test "reads a wider window than one sample" do
      media_item_fixture(%{media_downloaded_at: minutes_ago(40)})

      # Forty minutes of quiet after a download is still a working connection. Reading
      # only the last five would have the headline flickering to grey all day.
      assert %{state: :nominal, downloads: 1} = YoutubeStatus.current()
    end

    test "carries the window it measured" do
      current = YoutubeStatus.current(3)

      assert DateTime.diff(current.until, current.since) == 3 * 3600
    end
  end

  describe "history_buckets/2" do
    test "covers the whole range whether or not anything was written" do
      buckets = YoutubeStatus.history_buckets(24, 96)

      assert length(buckets) == 96
      # A stretch nothing was measuring is not a stretch where nothing happened.
      assert Enum.all?(buckets, &(&1.state == :no_data))
    end

    test "the worst reading in a bucket is the one it shows" do
      sample_at(minutes_ago(10), :nominal)
      sample_at(minutes_ago(12), :blocked)

      # Both fall in the same quarter hour. A block that lasted ten minutes still colours
      # its segment red, which is the whole point of a history bar.
      assert Enum.any?(YoutubeStatus.history_buckets(24, 96), &(&1.state == :blocked))
    end

    test "a green sample beats an idle one" do
      sample_at(minutes_ago(10), :nominal)
      sample_at(minutes_ago(12), :idle)

      refute Enum.any?(YoutubeStatus.history_buckets(24, 96), &(&1.state == :idle))
      assert Enum.any?(YoutubeStatus.history_buckets(24, 96), &(&1.state == :nominal))
    end

    test "adds up the counts of everything in the bucket" do
      Repo.insert!(%StatusSample{state: :nominal, window_seconds: 300, downloads: 2, inserted_at: minutes_ago(10)})
      Repo.insert!(%StatusSample{state: :nominal, window_seconds: 300, downloads: 3, inserted_at: minutes_ago(12)})

      bucket = Enum.find(YoutubeStatus.history_buckets(24, 96), &(&1.samples == 2))

      assert bucket.downloads == 5
    end
  end

  describe "prune!/0" do
    test "keeps the retention window and drops what is behind it" do
      for days <- [1, 45], do: sample_at(minutes_ago(days * 24 * 60))

      assert {1, _} = YoutubeStatus.prune!()
      assert Repo.aggregate(StatusSample, :count) == 1
    end
  end
end
