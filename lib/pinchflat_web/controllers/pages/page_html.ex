defmodule PinchflatWeb.Pages.PageHTML do
  use PinchflatWeb, :html

  embed_templates "page_html/*"

  @doc """
  What a state means, in the words someone would use to say it out loud.

  Returns binary()
  """
  def status_headline(:nominal), do: "Downloads are getting through"
  def status_headline(:degraded), do: "Indexing works, downloads do not"
  def status_headline(:blocked), do: "YouTube is refusing this address"
  def status_headline(:idle), do: "Nothing has been attempted"
  def status_headline(:disabled), do: "Stopped on purpose"

  @doc """
  The counts behind a reading, written out.

  Returns binary()
  """
  def status_detail(%{state: :disabled} = current, health) do
    "Nothing ran in the last #{window_phrase(current)}: #{quiet_cause(health)}. " <>
      "There is nothing to report about YouTube while that is true."
  end

  def status_detail(%{state: :idle} = current, _health) do
    "Nothing was downloaded or indexed in the last #{window_phrase(current)}, so there is nothing to report."
  end

  def status_detail(current, _health) do
    parts = [
      "#{current.downloads} downloaded",
      "#{current.connection_failures} refused#{throttle_aside(current)}",
      "#{current.indexing_successes} indexed"
    ]

    "In the last #{window_phrase(current)}: #{Enum.join(parts, ", ")}."
  end

  @doc """
  What one queue is actually doing, which is not the same as where its switch is set.

  Returns binary()
  """
  def switch_status(%{paused: true, backoff_until: nil}), do: "stopped by hand"

  def switch_status(%{paused: true, backoff_until: until}),
    do: "stopped by hand, and held by the backoff until #{local_time(until)}"

  def switch_status(%{backoff_until: nil}), do: "running"
  def switch_status(%{backoff_until: until}), do: "paused by the backoff until #{local_time(until)}"

  @doc """
  The dot beside a queue: blue when somebody stopped it, orange when the backoff is
  holding it, green when it is genuinely running.

  Returns binary()
  """
  def switch_colour(%{paused: true}), do: "bg-meta-5"
  def switch_colour(%{backoff_until: nil}), do: "bg-meta-3"
  def switch_colour(_switch), do: "bg-meta-8"

  @doc """
  Whether pressing the button will change what the queue does, as opposed to only where
  its switch is set. Starting a queue the backoff is holding is a real change that has no
  visible effect until the pause ends, and saying so beats letting somebody press it twice.

  Returns boolean()
  """
  def switch_takes_effect_now?(%{paused: true, backoff_until: nil}), do: true
  def switch_takes_effect_now?(%{paused: true}), do: false
  def switch_takes_effect_now?(_switch), do: true

  @doc """
  The name of a range, as a tab reads it.

  Returns binary()
  """
  def range_label(range), do: range |> to_string() |> String.capitalize()

  @doc """
  How far back a range reaches, in words.

  Returns binary()
  """
  def range_span(:hour), do: "hour"
  def range_span(:day), do: "24 hours"
  def range_span(:week), do: "7 days"
  def range_span(:month), do: "30 days"

  @doc """
  The same span as the far end of the bar reads it. "Last hour" is right above the bar and
  "hour ago" underneath it is not.

  Returns binary()
  """
  def range_ago(:hour), do: "1 hour ago"
  def range_ago(range), do: "#{range_span(range)} ago"

  @doc """
  What one segment of the history bar covers.

  Returns binary()
  """
  def bucket_tooltip(%{state: :no_data} = bucket) do
    "#{bucket_time(bucket)} - nothing was measuring"
  end

  def bucket_tooltip(%{state: :idle} = bucket) do
    "#{bucket_time(bucket)} - nothing attempted"
  end

  def bucket_tooltip(%{state: :disabled} = bucket) do
    "#{bucket_time(bucket)} - stopped by hand"
  end

  def bucket_tooltip(bucket) do
    "#{bucket_time(bucket)} - #{bucket.downloads} downloaded, " <>
      "#{bucket.connection_failures} refused, #{bucket.indexing_successes} indexed"
  end

  @doc """
  Why the yt-dlp queues are or are not running, in one phrase.

  Three different reasons stop them and only one of them lifts itself, so "paused" on its
  own would answer the wrong question.

  Returns binary()
  """
  def queues_summary(health) do
    case stopped_by_hand(health) do
      [] -> nil
      names -> "#{Enum.join(names, " and ")} stopped by hand"
    end
  end

  # Both causes can be true at once, and a page that named only one would be answering
  # half the question.
  defp quiet_cause(health) do
    backoff =
      if health.queues_paused_until,
        do: "the backoff is holding the queues until #{local_time(health.queues_paused_until)}"

    switches =
      case stopped_by_hand(health) do
        [] -> nil
        names -> "#{Enum.join(names, " and ")} is stopped by hand"
      end

    [backoff, switches] |> Enum.reject(&is_nil/1) |> Enum.join(", and ")
  end

  defp stopped_by_hand(health) do
    [{:indexing, health.indexing_paused}, {:downloading, health.downloading_paused}]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&to_string(elem(&1, 0)))
  end

  defp local_time(datetime) do
    timezone = Application.get_env(:pinchflat, :timezone)

    Calendar.strftime(Timex.Timezone.convert(datetime, timezone), "%H:%M")
  end

  @doc """
  The fill for a state. Written out in full rather than built from a fragment, because
  Tailwind only ships the classes it can find in the source.

  Returns binary()
  """
  def status_colour(:nominal), do: "bg-meta-3"
  def status_colour(:degraded), do: "bg-meta-8"
  def status_colour(:blocked), do: "bg-meta-1"
  # A mid grey rather than one of the theme's near-black tones. Idle and no_data are
  # different facts and both were dark enough to read as the same absence.
  def status_colour(:idle), do: "bg-slate-600"
  def status_colour(:disabled), do: "bg-meta-5"
  def status_colour(:no_data), do: "bg-boxdark-2"

  @doc """
  The border for the headline card, so the page reads at a glance without relying on the
  dot alone.

  Returns binary()
  """
  def status_border(:nominal), do: "border-meta-3"
  def status_border(:degraded), do: "border-meta-8"
  def status_border(:blocked), do: "border-meta-1"
  def status_border(:idle), do: "border-strokedark"
  def status_border(:disabled), do: "border-meta-5"

  defp throttle_aside(%{throttle_failures: 0}), do: ""
  defp throttle_aside(%{throttle_failures: count}), do: " (#{count} throttled)"

  defp window_phrase(%{since: since, until: until}) do
    case div(DateTime.diff(until, since), 3600) do
      1 -> "hour"
      hours -> "#{hours} hours"
    end
  end

  # A time with no date is ambiguous the moment a segment covers more than a day, which is
  # every segment on the week and month views.
  defp bucket_time(bucket) do
    timezone = Application.get_env(:pinchflat, :timezone)
    format = if DateTime.diff(bucket.to, bucket.from) < 86_400, do: "%d %b, %H:%M", else: "%d %b"

    Calendar.strftime(Timex.Timezone.convert(bucket.from, timezone), format)
  end
end
