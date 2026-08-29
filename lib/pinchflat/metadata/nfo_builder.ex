defmodule Pinchflat.Metadata.NfoBuilder do
  @moduledoc """
  Provides methods for building and storing NFO files for
  use by Kodi/Jellyfin and other media center software.
  """

  import Pinchflat.Utils.XmlUtils, only: [safe: 1]

  alias Pinchflat.Utils.FilesystemUtils
  alias Pinchflat.Metadata.MetadataFileHelpers

  # Both orders, because channels use either. Dashes first: an en or em dash inside a
  # title is far rarer than one used as a separator.
  @title_separators [" - ", " – ", " — ", " | ", " · "]

  # yt-dlp's own names for a channel's tabs, and nothing else.
  @collection_suffixes ~w(Videos Shorts Live Streams Releases Playlists Podcasts)

  @doc """
  Builds an NFO file for a media item (read: single "episode") and
  stores it at the specified location.

  Returns the filepath of the NFO file.
  """
  def build_and_store_for_media_item(nfo_filepath, metadata, media_profile \\ nil) do
    nfo = build_for_media_item(nfo_filepath, metadata, media_profile)

    FilesystemUtils.write_p!(nfo_filepath, nfo)

    nfo_filepath
  end

  @doc """
  Builds an NFO file for a souce and stores it at the specified location.
  Technically works for playlists, but it's really made for channels.

  Returns the filepath of the NFO file.
  """
  def build_and_store_for_source(filepath, metadata, media_profile \\ nil) do
    nfo = build_for_source(metadata, media_profile)

    FilesystemUtils.write_p!(filepath, nfo)

    filepath
  end

  defp build_for_media_item(nfo_filepath, metadata, media_profile) do
    upload_date = MetadataFileHelpers.parse_upload_date(metadata["upload_date"])
    # NOTE: the filepath here isn't the path of the media item, it's the path that
    # the NFO should be saved to. This works because the NFO's path is the same as
    # the media's path, just with a different extension. If this ever changes I'll
    # need to pass in the media item's path as well.
    {season, episode} = determine_season_and_episode_number(nfo_filepath, upload_date)

    # Cribbed from a combination of the Kodi wiki, ytdl-nfo, and ytdl-sub.
    #
    # NOTE: <aired> is a date, not a datetime. Jellyfin matches this field against its
    # ReleaseDateFormat setting - `yyyy-MM-dd` by default, and an exact match at that - so
    # a datetime parses as no date at all and the episode silently loses its air date.
    # Everything else in the file is unaffected, which is what makes it hard to spot.
    # `upload_date` stays a DateTime because determine_season_and_episode_number/2 reads
    # its .year below.
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
    <episodedetails>
      <title>#{safe(episode_title(metadata, media_profile))}</title>
      <showtitle>#{safe(metadata["uploader"])}</showtitle>
      <uniqueid type="youtube" default="true">#{safe(metadata["id"])}</uniqueid>
      <plot>#{safe(metadata["description"])}</plot>
      <aired>#{safe(DateTime.to_date(upload_date))}</aired>
      <season>#{safe(season)}</season>
      <episode>#{episode}</episode>
      <genre>YouTube</genre>
    </episodedetails>
    """
  end

  defp build_for_source(metadata, media_profile) do
    """
    <?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
    <tvshow>
      <title>#{safe(show_title(metadata, media_profile))}</title>
      <plot>#{safe(metadata["description"])}</plot>
      <uniqueid type="youtube" default="true">#{safe(metadata["id"])}</uniqueid>
      <genre>YouTube</genre>
    </tvshow>
    """
  end

  # In a media centre the channel is already the name of the series, so a title that
  # repeats it spends the width twice. The uploader is still in <showtitle>, so nothing
  # is lost - and if stripping would leave an empty title, the original is kept, because
  # a blank episode name is worse than a repetitive one.
  defp episode_title(metadata, %{nfo_strip_uploader_from_title: true}) do
    title = to_string(metadata["title"])
    uploader = to_string(metadata["uploader"])

    if uploader == "" do
      title
    else
      stripped =
        @title_separators
        |> Enum.reduce(title, fn separator, acc ->
          acc
          |> String.replace_suffix("#{separator}#{uploader}", "")
          |> String.replace_prefix("#{uploader}#{separator}", "")
        end)
        |> String.trim()

      if stripped == "", do: title, else: stripped
    end
  end

  defp episode_title(metadata, _media_profile), do: metadata["title"]

  # A source declared on a channel's /videos tab is reported by yt-dlp as
  # "Whatever - Videos", and that suffix is the tab, not part of the name. Only yt-dlp's
  # own tab names are removed: the rest of a collection title belongs to the channel, and
  # something like "Golden Moustache (M6)" has to survive untouched.
  defp show_title(metadata, %{nfo_strip_collection_suffix: true}) do
    title = to_string(metadata["title"])

    Enum.reduce(@collection_suffixes, title, fn suffix, acc ->
      acc |> String.replace_suffix(" - #{suffix}", "") |> String.trim()
    end)
    |> case do
      "" -> title
      stripped -> stripped
    end
  end

  defp show_title(metadata, _media_profile), do: metadata["title"]

  defp determine_season_and_episode_number(filepath, upload_date) do
    case MetadataFileHelpers.season_and_episode_from_media_filepath(filepath) do
      {:ok, {season, episode}} -> {season, episode}
      {:error, _} -> {upload_date.year, Calendar.strftime(upload_date, "%m%d")}
    end
  end
end
