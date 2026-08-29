defmodule Pinchflat.Downloading.DownloadErrors do
  @moduledoc """
  What yt-dlp's download failures mean, in one place.

  These messages were matched in three modules that each kept their own list, and the
  lists disagreed. `"Sign in to confirm"` appeared as a prefix in two of them and covered
  both `...your age`, which is permanent, and `...you're not a bot`, which clears on its
  own - so a throttle was abandoned as though it were an age restriction in one place and
  retried with the user's cookies in another.

  Three copies of a rule are three chances to drift. The table below is the rule.

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

  @errors [
    %{
      key: :throttled,
      pattern: "Sign in to confirm you're not a bot",
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
      pattern: "This video is available to this channel's members",
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

  defp find(message) do
    message = to_string(message)

    Enum.find(@errors, &String.contains?(message, &1.pattern))
  end
end
