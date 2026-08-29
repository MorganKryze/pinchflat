defmodule PinchflatWeb.Api.ApiController do
  @moduledoc """
  A read-only JSON view of sources and media, for scripts.

  Everything Pinchflat can be asked was previously only reachable through the HTML: a
  CSRF token scraped out of a page, forms that replace every field they carry so
  forgetting one blanks it, and `/sources` rendered by a LiveView that pages ten at a
  time over a websocket with no `?page=` to override. Listing the sources at all meant
  walking ids until enough 404s came back.

  Responses are built from explicit maps rather than by encoding the schemas. It is more
  typing and it is the point: a field is in the API because someone put it there, so
  adding a column cannot quietly publish it.

  Protected by `route_token`, which is the same trade the OPML feed already makes. It
  travels in the query string, so it belongs behind a reverse proxy rather than on the
  open internet.
  """

  use PinchflatWeb, :controller

  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Media
  alias Pinchflat.Sources
  alias Pinchflat.Media.MediaItem

  # A cap rather than a default: a script asking for everything gets everything up to
  # here, and one that asks for more than the library holds is not an error.
  @max_limit 500
  @default_limit 100

  def sources(conn, _params) do
    sources = Sources.list_sources()

    json(conn, %{data: Enum.map(sources, &source_json/1)})
  end

  def source(conn, %{"id" => id}) do
    json(conn, %{data: source_json(Sources.get_source!(id))})
  end

  @doc """
  Media for a source, optionally narrowed to one state.

  `state` accepts `pending`, `downloaded`, `errored` or `other` - the same four the source
  page shows as tabs, so what a script sees and what a person sees cannot drift apart.
  """
  def source_media(conn, %{"source_id" => source_id} = params) do
    source = Sources.get_source!(source_id)
    {limit, offset} = page_params(params)

    media_items =
      source
      |> media_query(params["state"])
      |> order_by([mi], desc: mi.id)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    json(conn, %{data: Enum.map(media_items, &media_item_json/1), limit: limit, offset: offset})
  end

  def media_item(conn, %{"id" => id}) do
    json(conn, %{data: media_item_json(Media.get_media_item!(id))})
  end

  defp media_query(source, "pending") do
    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(^dynamic(^MediaQuery.for_source(source) and ^MediaQuery.pending()))
  end

  defp media_query(source, "downloaded") do
    where(MediaItem, ^dynamic(^MediaQuery.for_source(source) and ^MediaQuery.downloaded()))
  end

  defp media_query(source, "errored") do
    where(MediaItem, ^dynamic(^MediaQuery.for_source(source) and ^MediaQuery.errored()))
  end

  defp media_query(source, "other") do
    MediaQuery.new()
    |> MediaQuery.require_assoc(:media_profile)
    |> where(
      ^dynamic(
        ^MediaQuery.for_source(source) and
          (not (^MediaQuery.downloaded()) and not (^MediaQuery.pending()))
      )
    )
  end

  # An unrecognised state returns everything rather than nothing. Nothing would look
  # exactly like a source with no media, and a script cannot tell those apart.
  defp media_query(source, _state), do: where(MediaItem, ^MediaQuery.for_source(source))

  defp page_params(params) do
    limit =
      case Integer.parse(params["limit"] || "") do
        {n, _} when n > 0 -> min(n, @max_limit)
        _ -> @default_limit
      end

    offset =
      case Integer.parse(params["offset"] || "") do
        {n, _} when n >= 0 -> n
        _ -> 0
      end

    {limit, offset}
  end

  defp source_json(source) do
    %{
      id: source.id,
      uuid: source.uuid,
      custom_name: source.custom_name,
      collection_name: source.collection_name,
      collection_type: source.collection_type,
      original_url: source.original_url,
      enabled: source.enabled,
      download_media: source.download_media,
      media_profile_id: source.media_profile_id,
      index_frequency_minutes: source.index_frequency_minutes,
      last_indexed_at: source.last_indexed_at
    }
  end

  defp media_item_json(media_item) do
    %{
      id: media_item.id,
      uuid: media_item.uuid,
      title: media_item.title,
      media_id: media_item.media_id,
      source_id: media_item.source_id,
      original_url: media_item.original_url,
      uploaded_at: media_item.uploaded_at,
      media_downloaded_at: media_item.media_downloaded_at,
      media_filepath: media_item.media_filepath,
      prevent_download: media_item.prevent_download,
      blocked_reason: media_item.blocked_reason,
      last_error: media_item.last_error,
      last_error_at: media_item.last_error_at
    }
  end
end
