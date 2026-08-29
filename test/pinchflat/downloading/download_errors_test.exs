defmodule Pinchflat.Downloading.DownloadErrorsTest do
  use Pinchflat.DataCase, async: true

  alias Pinchflat.Downloading.DownloadErrors

  # The exact strings yt-dlp emits, with the surrounding noise it emits them in. Matching
  # on a trimmed version would pass here and fail in production.
  @not_a_bot "ERROR: [youtube] abc123: Sign in to confirm you're not a bot. Use --cookies-from-browser or --cookies for the authentication."
  @your_age "ERROR: [youtube] abc123: Sign in to confirm your age. This video may be inappropriate for some users."
  @members "ERROR: [youtube] abc123: This video is available to this channel's members on level: Supporter."
  @unavailable "ERROR: [youtube] abc123: Video unavailable. This video is no longer available."

  describe "the two 'Sign in to confirm' messages" do
    test "are not the same thing" do
      # One prefix covered both for as long as this bug existed. They are opposites.
      assert DownloadErrors.classify(@not_a_bot) == :throttled
      assert DownloadErrors.classify(@your_age) == :age_restricted
    end

    test "a throttle is worth retrying and an age restriction is not" do
      assert DownloadErrors.retryable?(@not_a_bot)
      refute DownloadErrors.retryable?(@your_age)
    end

    test "cookies can fix an age restriction and cannot lift a throttle" do
      # Retrying a throttle with cookies spends twice the requests during a block and
      # presents an account's session at the worst possible moment.
      refute DownloadErrors.fixable_with_cookies?(@not_a_bot)
      assert DownloadErrors.fixable_with_cookies?(@your_age)
    end

    test "only the throttle stops the queues" do
      assert DownloadErrors.throttled?(@not_a_bot)
      refute DownloadErrors.throttled?(@your_age)
    end
  end

  describe "classify/1" do
    test "recognises the rest" do
      assert DownloadErrors.classify(@members) == :members_only
      assert DownloadErrors.classify(@unavailable) == :unavailable
    end

    test "does not guess" do
      assert DownloadErrors.classify("HTTP Error 500") == :unknown
      assert DownloadErrors.classify(nil) == :unknown
    end
  end

  describe "retryable?/1" do
    test "an unknown failure is retried" do
      # Upstream's behaviour, and the safer default: giving up on something that would
      # have worked loses a media item silently.
      assert DownloadErrors.retryable?("HTTP Error 500")
    end
  end

  describe "label/1" do
    test "gives something short enough to read in a table" do
      assert DownloadErrors.label(@not_a_bot) == "Throttled by YouTube"
      assert String.length(DownloadErrors.label(@members)) < 30
    end

    test "is nil for a message it does not know" do
      # No invented label: the raw text is shown instead, which is honest about the fact
      # that nothing here understood it.
      assert DownloadErrors.label("HTTP Error 500") == nil
    end
  end

  describe "throttle_pattern/0" do
    test "is what the throttle entry matches on" do
      # The health summary counts throttles in SQL, so it needs the string. If these two
      # ever disagreed, a backoff would trigger on something the counts never saw.
      assert DownloadErrors.classify(DownloadErrors.throttle_pattern()) == :throttled
    end
  end
end
