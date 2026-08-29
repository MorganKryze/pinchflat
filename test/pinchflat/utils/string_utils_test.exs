defmodule Pinchflat.Utils.StringUtilsTest do
  use Pinchflat.DataCase

  alias Pinchflat.Utils.StringUtils

  describe "to_kebab_case/1" do
    test "converts a space-delimited string to kebab-case" do
      assert StringUtils.to_kebab_case("hello world") == "hello-world"
    end

    test "converts an underscore-delimited string to kebab-case" do
      assert StringUtils.to_kebab_case("hello_world") == "hello-world"
    end
  end

  describe "random_string/1" do
    test "generates a random string" do
      assert is_binary(StringUtils.random_string())
      assert StringUtils.random_string() != StringUtils.random_string()
    end

    test "has a defined default length" do
      assert String.length(StringUtils.random_string()) == 32
    end

    test "can generate a string of a given length" do
      assert String.length(StringUtils.random_string(64)) == 64
    end
  end

  describe "double_brace/1" do
    test "wraps a string in double braces" do
      assert StringUtils.double_brace("hello") == "{{ hello }}"
    end
  end

  describe "wrap_string/1" do
    test "returns strings as-is" do
      assert StringUtils.wrap_string("hello") == "hello"
    end

    test "returns other values as inspected strings" do
      assert StringUtils.wrap_string(1) == "1"
    end
  end

  describe "strip_urls/1" do
    test "keeps the sentence an URL was buried in" do
      # The case that made dropping whole lines untenable: the line is the content and
      # the URL is the appendage.
      text = "Max et Léon sort en DVD le 7 mars ! (précommande ici https://example.com/dvd)"

      assert StringUtils.strip_urls(text) =~ "Max et Léon sort en DVD le 7 mars !"
      refute StringUtils.strip_urls(text) =~ "example.com"
    end

    test "drops a line that was nothing but a link" do
      text = "Real content\nhttps://example.com/subscribe\nMore content"

      assert StringUtils.strip_urls(text) == "Real content\nMore content"
    end

    test "drops a line left as punctuation debris" do
      # "(  )" survives a naive strip and reads as corruption.
      text = "Real content\n( https://example.com )\nMore content"

      assert StringUtils.strip_urls(text) == "Real content\nMore content"
    end

    test "keeps blank lines, which are paragraph breaks" do
      text = "First paragraph\n\nSecond paragraph"

      assert StringUtils.strip_urls(text) == text
    end

    test "leaves text with no URLs alone" do
      assert StringUtils.strip_urls("Nothing to see here") == "Nothing to see here"
    end

    test "handles http as well as https" do
      assert StringUtils.strip_urls("see http://example.com now") == "see now"
    end

    test "passes anything that is not a string straight through" do
      assert StringUtils.strip_urls(nil) == nil
    end
  end

  describe "truncate/2" do
    test "leaves text that already fits" do
      assert StringUtils.truncate("short", 100) == "short"
    end

    test "cuts at a word boundary rather than mid-word" do
      # Mid-word reads as corruption; a clean break reads as a summary.
      result = StringUtils.truncate("the quick brown fox jumps", 12)

      assert result == "the quick…"
    end

    test "cuts hard when there is no boundary to respect" do
      assert StringUtils.truncate("supercalifragilistic", 5) == "super…"
    end

    test "does nothing without a positive limit" do
      assert StringUtils.truncate("anything", nil) == "anything"
      assert StringUtils.truncate("anything", 0) == "anything"
    end
  end
end
