defmodule Pinchflat.Utils.StringUtils do
  @moduledoc """
  Utility methods for working with strings
  """

  @doc """
  Converts a string to kebab-case (ie: `hello world` -> `hello-world`)

  Returns binary()
  """
  def to_kebab_case(string) do
    string
    |> String.replace(~r/[\s_]/, "-")
    |> String.downcase()
  end

  @doc """
  Returns a random string of the given length. Base 16 encoded, lower case.

  Returns binary()
  """
  def random_string(length \\ 32) do
    :crypto.strong_rand_bytes(length)
    |> Base.encode16(case: :lower)
    |> String.slice(0..(length - 1))
  end

  @doc """
  Wraps a string in double braces. Useful as a UI helper now that
  LiveView 1.0.0 allows `{}` for interpolation so now we can't use braces
  directly in the view.

  Returns binary()
  """
  def double_brace(string) do
    "{{ #{string} }}"
  end

  @doc """
  Wraps a string in quotes if it's not already a string. Useful for working with
  error messages whose types can vary.

  Returns binary()
  """
  def wrap_string(message) when is_binary(message), do: message
  def wrap_string(message), do: "#{inspect(message)}"

  @doc """
  Removes URLs from a block of text, keeping the sentences they were embedded in.

  Dropping the whole line an URL appears on is the obvious implementation and it is
  wrong: a YouTube description is full of lines like "Out on DVD March 7th! (pre-order
  here https://...)", where the line is the content and the URL is the appendage. On one
  library that approach emptied a tenth of the descriptions outright.

  A line is only dropped once removing the URL leaves nothing with a letter or a digit in
  it, which is what catches the leftover brackets and dashes that would otherwise survive
  as debris.

  Returns binary()
  """
  def strip_urls(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.map(fn line -> {line, strip_urls_from_line(line)} end)
    # Only lines this actually changed can be dropped. A line that was already blank is a
    # paragraph break and stays; one left blank or as bracket debris by the strip does not,
    # since keeping it would leave a hole where the link used to be.
    |> Enum.reject(fn {original, stripped} -> original != stripped and not has_content?(stripped) end)
    |> Enum.map_join("\n", fn {_original, stripped} -> stripped end)
  end

  def strip_urls(text), do: text

  defp strip_urls_from_line(line) do
    line
    |> String.replace(~r{https?://\S+}i, "")
    |> String.replace(~r{[ \t]+}, " ")
    |> String.trim()
  end

  defp has_content?(line), do: String.match?(line, ~r/[\p{L}\p{N}]/u)

  @doc """
  Shortens text to at most `max` characters, cutting at a word boundary and marking that
  something was removed.

  Cutting mid-word reads as corruption rather than as a summary, so the last space before
  the limit wins - unless there is no space at all, in which case there is nothing to
  respect and a hard cut is the honest answer.

  Returns binary()
  """
  def truncate(text, max) when is_binary(text) and is_integer(max) and max > 0 do
    if String.length(text) <= max do
      text
    else
      cut = String.slice(text, 0, max)

      case String.split(cut, ~r/\s/) do
        parts when length(parts) > 1 -> parts |> Enum.drop(-1) |> Enum.join(" ")
        _ -> cut
      end
      |> String.trim_trailing()
      |> Kernel.<>("…")
    end
  end

  def truncate(text, _max), do: text
end
