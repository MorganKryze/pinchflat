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

  describe "the message yt-dlp actually writes" do
    # Copied from production logs, apostrophe included. Every other fixture in this repo
    # was typed by hand with an ASCII apostrophe, so every test agreed with the bug: on a
    # real instance `throttled?/1` was false for all fifty-four refusals in half an hour,
    # the backoff could not arm, and its threshold counted zero.
    @real_throttle "ERROR: [youtube] y1nTvXlf3Uo: Sign in to confirm you\u2019re not a bot. Use --cookies-from-browser or --cookies for the authentication. See https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp"
    @real_members "ERROR: [youtube] abc: Join this channel to get access to members-only content like this video. This video is available to this channel\u2019s members on level: Patron."

    test "a throttle is recognised" do
      assert DownloadErrors.classify(@real_throttle) == :throttled
      assert DownloadErrors.throttled?(@real_throttle)
      assert DownloadErrors.retryable?(@real_throttle)
      refute DownloadErrors.fixable_with_cookies?(@real_throttle)
    end

    test "members-only is recognised" do
      # The other pattern with an apostrophe in it. This one failed quietly in the other
      # direction: the item stayed retryable forever and cookies were never offered.
      assert DownloadErrors.classify(@real_members) == :members_only
      refute DownloadErrors.retryable?(@real_members)
      assert DownloadErrors.fixable_with_cookies?(@real_members)
    end

    test "the ASCII spelling still works" do
      assert DownloadErrors.throttled?("Sign in to confirm you're not a bot")
    end
  end

  describe "the patterns themselves" do
    test "are ASCII, so SQL and Elixir cannot disagree about them" do
      # `throttle_failures_since/1` matches in SQL, where the normalising in `find/1` is
      # not available. A pattern needing it would behave differently depending on who
      # asked - which is the shape of the bug that got here in the first place.
      for %{key: key, pattern: pattern} <- DownloadErrors.all() do
        assert pattern == for(<<c <- pattern>>, c < 128, into: "", do: <<c>>),
               "#{key} has a pattern SQL cannot match: #{inspect(pattern)}"
      end
    end

    test "none of them matches the age gate as well as the throttle" do
      age = "Sign in to confirm your age"

      assert DownloadErrors.classify(age) == :age_restricted
      refute DownloadErrors.throttled?(age)
    end
  end
end
