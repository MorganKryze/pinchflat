defmodule Pinchflat.Metadata.NfoBuilderTest do
  use Pinchflat.DataCase

  alias Pinchflat.Metadata.NfoBuilder
  alias Pinchflat.Utils.FilesystemUtils

  setup do
    filepath = FilesystemUtils.generate_metadata_tmpfile(:nfo)

    on_exit(fn -> File.rm!(filepath) end)

    {:ok,
     %{
       metadata: render_parsed_metadata(:media_metadata),
       filepath: filepath
     }}
  end

  describe "build_and_store_for_media_item/2" do
    test "returns the filepath", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)

      assert File.exists?(result)
    end

    test "builds an NFO file", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, ~S(<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>))
      assert String.contains?(nfo, "<title>#{metadata["title"]}</title>")
    end

    test "produces well-formed XML", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)

      # Every other assertion here is a String.contains?, which cannot see anything the
      # template emits that it should not. Parsing the whole file can, and a media centre
      # reading a malformed NFO is the case nobody notices until dates or titles quietly
      # stop appearing.
      assert {_parsed, []} = :xmerl_scan.string(String.to_charlist(File.read!(result)))
    end

    test "renders the aired date as a plain date", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      # Not a datetime: Jellyfin parses this field in the exact format its
      # ReleaseDateFormat setting names, `yyyy-MM-dd` by default, and anything else
      # leaves the episode with no air date at all.
      assert String.contains?(nfo, "<aired>2021-07-20</aired>")
    end

    test "escapes invalid characters", %{filepath: filepath} do
      metadata = %{
        "title" => "hello' & <world>",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "hello&#39; &amp; &lt;world&gt;")
    end

    test "uses the season and episode number from the filepath if it can be determined" do
      metadata = %{
        "title" => "title",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      tmpfile_directory = Application.get_env(:pinchflat, :tmpfile_directory)
      filepath = Path.join([tmpfile_directory, "foo/s0123e456.nfo"])

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "<season>0123</season>")
      assert String.contains?(nfo, "<episode>456</episode>")

      File.rm!(filepath)
    end

    test "uses the upload date if the season and episode number can't be determined", %{filepath: filepath} do
      metadata = %{
        "title" => "title",
        "uploader" => "uploader",
        "id" => "id",
        "description" => "description",
        "upload_date" => "20210101"
      }

      result = NfoBuilder.build_and_store_for_media_item(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "<season>2021</season>")
      assert String.contains?(nfo, "<episode>0101</episode>")
    end
  end

  describe "build_and_store_for_media_item/3 when stripping the uploader from the title" do
    setup %{filepath: filepath} do
      {:ok, %{filepath: filepath, profile: %{nfo_strip_uploader_from_title: true}}}
    end

    defp title_for(filepath, profile, title, uploader) do
      metadata = %{
        "title" => title,
        "uploader" => uploader,
        "id" => "id",
        "description" => "d",
        "upload_date" => "20210720"
      }

      filepath
      |> NfoBuilder.build_and_store_for_media_item(metadata, profile)
      |> File.read!()
      |> then(&Regex.run(~r{<title>(.*)</title>}, &1))
      |> Enum.at(1)
    end

    test "takes it off the end", %{filepath: filepath, profile: profile} do
      assert title_for(filepath, profile, "Quand on fait ses adieux - Palmashow", "Palmashow") ==
               "Quand on fait ses adieux"
    end

    test "takes it off the front", %{filepath: filepath, profile: profile} do
      assert title_for(filepath, profile, "Palmashow | Les bons profs", "Palmashow") == "Les bons profs"
    end

    test "leaves a title that does not repeat it", %{filepath: filepath, profile: profile} do
      assert title_for(filepath, profile, "Les bons profs", "Palmashow") == "Les bons profs"
    end

    test "does not strip a name that merely appears mid-title", %{filepath: filepath, profile: profile} do
      # Only a separator-delimited prefix or suffix. Cutting the name wherever it appears
      # would mangle titles that are about the channel rather than signed by it.
      assert title_for(filepath, profile, "Le jour où Palmashow a tout cassé", "Palmashow") ==
               "Le jour où Palmashow a tout cassé"
    end

    test "keeps the original rather than emptying the title", %{filepath: filepath, profile: profile} do
      # A blank episode name in a media centre is worse than a repetitive one.
      assert title_for(filepath, profile, "Palmashow", "Palmashow") == "Palmashow"
    end

    test "does nothing when the option is off", %{filepath: filepath} do
      assert title_for(filepath, %{nfo_strip_uploader_from_title: false}, "Adieux - Palmashow", "Palmashow") ==
               "Adieux - Palmashow"
    end
  end

  describe "build_and_store_for_source/3 when stripping the collection suffix" do
    defp show_title_for(filepath, profile, title) do
      filepath
      |> NfoBuilder.build_and_store_for_source(%{"title" => title, "description" => "d", "id" => "id"}, profile)
      |> File.read!()
      |> then(&Regex.run(~r{<title>(.*)</title>}, &1))
      |> Enum.at(1)
    end

    test "removes yt-dlp's tab name", %{filepath: filepath} do
      profile = %{nfo_strip_collection_suffix: true}

      assert show_title_for(filepath, profile, "Palmashow - Videos") == "Palmashow"
      assert show_title_for(filepath, profile, "Palmashow - Shorts") == "Palmashow"
    end

    test "leaves everything that is part of the channel's name", %{filepath: filepath} do
      # The warning that made this narrow: only yt-dlp's own tab names come off. The rest
      # of a collection title belongs to the channel.
      profile = %{nfo_strip_collection_suffix: true}

      assert show_title_for(filepath, profile, "Golden Moustache (M6)") == "Golden Moustache (M6)"
      assert show_title_for(filepath, profile, "Videos From Home") == "Videos From Home"
      assert show_title_for(filepath, profile, "Radio - Live Sessions") == "Radio - Live Sessions"
    end

    test "does nothing when the option is off", %{filepath: filepath} do
      assert show_title_for(filepath, %{nfo_strip_collection_suffix: false}, "Palmashow - Videos") ==
               "Palmashow - Videos"
    end
  end

  describe "build_and_store_for_source/2" do
    test "returns the filepath", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_source(filepath, metadata)

      assert File.exists?(result)
    end

    test "builds an NFO file", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_source(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, ~S(<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>))
      assert String.contains?(nfo, "<title>#{metadata["title"]}</title>")
    end

    test "produces well-formed XML", %{metadata: metadata, filepath: filepath} do
      result = NfoBuilder.build_and_store_for_source(filepath, metadata)

      assert {_parsed, []} = :xmerl_scan.string(String.to_charlist(File.read!(result)))
    end

    test "escapes invalid characters", %{filepath: filepath} do
      metadata = %{
        "title" => "hello' & <world>",
        "description" => "description",
        "id" => "id"
      }

      result = NfoBuilder.build_and_store_for_source(filepath, metadata)
      nfo = File.read!(result)

      assert String.contains?(nfo, "hello&#39; &amp; &lt;world&gt;")
    end
  end
end
