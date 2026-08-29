defmodule Pinchflat.YtDlp.ConfigFilesTest do
  use Pinchflat.DataCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.YtDlp.ConfigFiles

  setup do
    dir = Path.join(Application.get_env(:pinchflat, :extras_directory), "yt-dlp-configs")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, %{dir: dir}}
  end

  defp write(dir, name, contents), do: File.write!(Path.join(dir, name), contents)

  defp paths(options), do: Enum.map(options, fn {:config_locations, path} -> Path.basename(path) end)

  describe "options_for/1 with a media item" do
    test "ignores a file that exists but is empty", %{dir: dir} do
      write(dir, "base-config.txt", "")
      media_item = media_item_fixture() |> Repo.preload(source: :media_profile)

      # The file Pinchflat creates on first boot is empty, and passing an empty config to
      # yt-dlp achieves nothing but noise in the logs.
      assert ConfigFiles.options_for(media_item) == []
    end

    test "orders least specific first, so the most specific wins", %{dir: dir} do
      media_item = media_item_fixture() |> Repo.preload(source: :media_profile)

      write(dir, "base-config.txt", "--socket-timeout 30")
      write(dir, "source-#{media_item.source_id}-config.txt", "--socket-timeout 60")

      # yt-dlp applies each --config-locations in turn, so the last one read wins.
      assert paths(ConfigFiles.options_for(media_item)) == [
               "base-config.txt",
               "source-#{media_item.source_id}-config.txt"
             ]
    end
  end

  describe "options_for_indexing/1" do
    test "gives indexing nothing by default", %{dir: dir} do
      source = source_fixture()
      write(dir, "base-config.txt", "--socket-timeout 30")

      # Upstream scopes the cascade to downloads on purpose, so an instance that has
      # changed nothing keeps that behaviour.
      assert ConfigFiles.options_for_indexing(source) == []
    end

    test "passes it once asked", %{dir: dir} do
      Settings.set(apply_yt_dlp_config_to_all_commands: true)
      source = source_fixture()
      write(dir, "base-config.txt", "--socket-timeout 30")

      assert paths(ConfigFiles.options_for_indexing(source)) == ["base-config.txt"]
    end

    test "never looks for a media item config", %{dir: dir} do
      Settings.set(apply_yt_dlp_config_to_all_commands: true)
      source = source_fixture()

      write(dir, "media-item-1-config.txt", "--socket-timeout 30")
      write(dir, "source-#{source.id}-config.txt", "--socket-timeout 60")

      # An indexing run covers a whole collection, so there is no media item whose config
      # could apply.
      assert paths(ConfigFiles.options_for_indexing(source)) == ["source-#{source.id}-config.txt"]
    end
  end
end
