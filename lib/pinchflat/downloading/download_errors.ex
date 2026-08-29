defmodule Pinchflat.Downloading.DownloadErrors do
  @moduledoc """
  What yt-dlp's download failures mean, in one place.

  These messages were matched in three modules that each kept their own list, and the
  lists disagreed. `"Sign in to confirm"` appeared as a prefix in two of them and covered
  both `...your age`, which is permanent, and `...you're not a bot`, which clears on its
  own - so a throttle was abandoned as though it were an age restriction in one place and
  retried with the user's cookies in another.

  Three copies of a rule are three chances to drift. The table below is the rule.

  ## Why the patterns are short, and plain ASCII

  yt-dlp writes `Sign in to confirm you\u2019re not a bot` with a typographic apostrophe. A
  pattern written with the ASCII one never matched it, and every test in this repo typed
  the ASCII one too, so the tests agreed with the bug. Nothing downstream noticed, because
  an unrecognised message is retryable and that is the right answer by accident - but
  `throttled?/1` was false for every throttle there has ever been, so the queue backoff
  could not arm, and its threshold counted zero out of fifty-four refusals.

  Two rules came out of that.

  A pattern is the shortest fragment that identifies the failure and nothing else. Matching
  a whole English sentence composed by another program is a bet on its punctuation.

  A pattern contains ASCII only, and there is a test that says so. `throttle_failures_since/1`
  matches in SQL, where none of the normalising below is available, so a pattern that needs
  normalising to work would be a rule that behaves differently depending on who asks.

  ## What each column decides

    * `retryable` - whether trying again could ever work. False means the worker stops
      rather than spending attempts on something that cannot succeed.
    * `fixable_with_cookies` - whether the download is worth retrying with the user's
      cookies attached. Cookies cannot lift a block on an address, so a throttle is not
      in this column: retrying one with cookies spends twice the requests during a block
      and presents an account's session at the worst possible moment.
    * `label` - what a person reads. yt-dlp's own text runs to hundreds of characters and
      is shown in a tooltip; the raw message is kept, but it is not the first thing seen.
  """

  # Order matters: the first pattern that matches wins. yt-dlp prints its warnings and its
  # verdict into one blob and all of it is kept in `last_error`, so a phrase can arrive
  # from a line that decided nothing - `Video unavailable in this format, trying another`
  # sits above a throttle on a real instance. A throttle is listed first for that reason:
  # it is the only one of these that is not a verdict on the video, so when both are in
  # the text it is the one that explains why nothing was downloaded. There is a test.
  @errors [
    %{
      key: :throttled,
      # Not "Sign in to confirm", which is also how the age gate opens - that prefix
      # covering two opposite messages is the defect this module was written for.
      pattern: "not a bot",
      label: "Throttled by YouTube",
      retryable: true,
      fixable_with_cookies: false
    },
    %{
      key: :age_restricted,
      pattern: "Sign in to confirm your age",
      label: "Age restricted",
      retryable: false,
      fixable_with_cookies: true
    },
    %{
      key: :members_only,
      pattern: "available to this channel",
      label: "Members only",
      retryable: false,
      fixable_with_cookies: true
    },
    %{
      key: :unavailable,
      pattern: "Video unavailable",
      label: "Video unavailable",
      retryable: false,
      fixable_with_cookies: false
    }
  ]

  @doc """
  Which known failure a message is, or `:unknown`.

  Returns atom()
  """
  def classify(message) do
    case find(message) do
      nil -> :unknown
      error -> error.key
    end
  end

  @doc """
  A short description of the failure, or nil if it is not one this knows about.

  Returns binary() | nil
  """
  def label(message) do
    case find(message) do
      nil -> nil
      error -> error.label
    end
  end

  @doc """
  Whether trying again could ever work.

  Unknown messages are retryable, which is both upstream's behaviour and the safer
  default: giving up on something that would have succeeded loses a media item silently,
  while retrying something hopeless costs a few attempts and stops.

  Returns boolean()
  """
  def retryable?(message) do
    case find(message) do
      nil -> true
      error -> error.retryable
    end
  end

  @doc """
  Whether the user's cookies could plausibly fix this.

  Returns boolean()
  """
  def fixable_with_cookies?(message) do
    case find(message) do
      nil -> false
      error -> error.fixable_with_cookies
    end
  end

  @doc """
  Whether this is YouTube refusing the address rather than the video. The only failure
  where the right response is to stop asking for a while.

  Returns boolean()
  """
  def throttled?(message), do: classify(message) == :throttled

  @doc """
  The message a throttle carries. Needed by the health summary, which counts throttles in
  SQL and so cannot use `classify/1`.

  Returns binary()
  """
  def throttle_pattern do
    Enum.find(@errors, &(&1.key == :throttled)).pattern
  end

  @doc """
  The failures this knows about, for callers that need the table rather than a verdict.

  Returns [map()]
  """
  def all, do: @errors

  # The typographic characters a message picks up on its way through YouTube and yt-dlp,
  # flattened to the ASCII the patterns are written in. Belt and braces: the patterns
  # avoid these characters entirely, and this means a future one that cannot avoid them
  # still matches.
  @typographic %{
    "\u2018" => "'",
    "\u2019" => "'",
    "\u201C" => "\"",
    "\u201D" => "\"",
    "\u2013" => "-",
    "\u2014" => "-",
    "\u00A0" => " "
  }

  defp find(message) do
    message = message |> to_string() |> normalise()

    Enum.find(@errors, &String.contains?(message, &1.pattern))
  end

  defp normalise(message) do
    Enum.reduce(@typographic, message, fn {from, to}, acc -> String.replace(acc, from, to) end)
  end
end
