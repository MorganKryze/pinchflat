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

  @doc """
  The counts behind a reading, written out.

  Returns binary()
  """
  def status_detail(%{state: :idle} = current) do
    "Nothing was downloaded or indexed in the last #{window_phrase(current)}, so there is nothing to report."
  end

  def status_detail(current) do
    parts = [
      "#{current.downloads} downloaded",
      "#{current.connection_failures} refused#{throttle_aside(current)}",
      "#{current.indexing_successes} indexed"
    ]

    "In the last #{window_phrase(current)}: #{Enum.join(parts, ", ")}."
  end

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

  def bucket_tooltip(bucket) do
    "#{bucket_time(bucket)} - #{bucket.downloads} downloaded, " <>
      "#{bucket.connection_failures} refused, #{bucket.indexing_successes} indexed"
  end

  @doc """
  The fill for a state. Written out in full rather than built from a fragment, because
  Tailwind only ships the classes it can find in the source.

  Returns binary()
  """
  def status_colour(:nominal), do: "bg-meta-3"
  def status_colour(:degraded), do: "bg-meta-8"
  def status_colour(:blocked), do: "bg-meta-1"
  def status_colour(:idle), do: "bg-meta-4"
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

  defp throttle_aside(%{throttle_failures: 0}), do: ""
  defp throttle_aside(%{throttle_failures: count}), do: " (#{count} throttled)"

  defp window_phrase(%{since: since, until: until}) do
    case div(DateTime.diff(until, since), 3600) do
      1 -> "hour"
      hours -> "#{hours} hours"
    end
  end

  defp bucket_time(bucket) do
    timezone = Application.get_env(:pinchflat, :timezone)

    Calendar.strftime(Timex.Timezone.convert(bucket.from, timezone), "%H:%M")
  end
end
