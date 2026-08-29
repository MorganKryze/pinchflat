defmodule Pinchflat.YtDlp.ConfigFiles do
  @moduledoc """
  Finds the yt-dlp config files that apply to a source or a media item.

  Files live under the extras directory in `yt-dlp-configs/`, and the ones that exist and
  have content are passed to yt-dlp as `--config-locations`. Ordered least specific first,
  because a later `--config-locations` wins: base, then media profile, then source, then
  the individual media item.

  Upstream applies this to downloads alone, and says so in a comment. That is a defensible
  scope for options about output paths and formats. It is the wrong one for a plugin
  directory, a socket timeout or a player-client override, which matter most while
  indexing - and on a real instance indexing was 88% of the yt-dlp calls made, none of
  which could see any of this.
  """

  alias Pinchflat.Settings
  alias Pinchflat.Sources.Source
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Utils.FilesystemUtils, as: FSUtils

  @doc """
  Config file options for a media item or a source, most specific last.

  A media item gets four levels; a source gets three, since the commands that take a
  source rather than a media item have no media item to look one up for.

  Returns [{:config_locations, binary()}]
  """
  def options_for(target)

  def options_for(%MediaItem{} = media_item) do
    build([
      "base-config.txt",
      "media-profile-#{media_item.source.media_profile_id}-config.txt",
      "source-#{media_item.source_id}-config.txt",
      "media-item-#{media_item.id}-config.txt"
    ])
  end

  def options_for(%Source{} = source) do
    build([
      "base-config.txt",
      "media-profile-#{source.media_profile_id}-config.txt",
      "source-#{source.id}-config.txt"
    ])
  end

  @doc """
  The same list, but only when the operator has asked for it.

  Downloads always get their config. Indexing and metadata get it only with
  `apply_yt_dlp_config_to_all_commands` set, because a base config written for downloads
  can contain options that mean nothing, or the wrong thing, to an indexing run.

  Returns [{:config_locations, binary()}]
  """
  def options_for_indexing(%Source{} = source) do
    if Settings.get!(:apply_yt_dlp_config_to_all_commands) do
      options_for(source)
    else
      []
    end
  end

  defp build(filenames) do
    base_dir = Path.join(Application.get_env(:pinchflat, :extras_directory), "yt-dlp-configs")

    filenames
    |> Enum.map(&Path.join(base_dir, &1))
    |> Enum.filter(&FSUtils.exists_and_nonempty?/1)
    |> Enum.map(&{:config_locations, &1})
  end
end
