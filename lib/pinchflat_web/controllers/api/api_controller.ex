defmodule PinchflatWeb.Api.ApiController do
  @moduledoc """
  A JSON view of sources and media, for scripts.

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

  The writes are narrow on purpose. Two things can be changed - whether a media item is
  set aside, and whether downloads are queued - because those are the two a script
  currently does by scraping. Everything else stays in the interface, where a form can
  explain itself.
  """

  use PinchflatWeb, :controller

  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Media
  alias Pinchflat.Sources
  alias Pinchflat.Media.MediaItem
  alias Pinchflat.Downloading.DownloadingHelpers

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

  @doc """
  Queues downloads for everything pending on a source.

  The same thing the "Force Download Pending" button does, at the same priority, so a
  script and a person asking for it get the same behaviour. Idempotent: the download
  worker's uniqueness means asking twice does not queue anything twice.
  """
  def create_source_downloads(conn, %{"source_id" => source_id}) do
    source = Sources.get_source!(source_id)

    DownloadingHelpers.enqueue_pending_download_tasks(source, priority: Settings.get!(:forced_download_priority))

    json(conn, %{data: %{source_id: source.id, queued: true}})
  end

  @doc """
  Queues a download for one media item, if it is something that should be downloaded.

  Returns 409 rather than pretending otherwise when it is not: a script that asked for a
  download and got a 200 is entitled to believe one is coming.
  """
  def create_media_item_download(conn, %{"media_item_id" => id}) do
    media_item = Media.get_media_item!(id)

    case DownloadingHelpers.kickoff_download_if_pending(media_item) do
      {:ok, _task} ->
        json(conn, %{data: %{media_item_id: media_item.id, queued: true}})

      {:error, :should_not_download} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "media item is not pending download", media_item_id: media_item.id})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "could not queue the download", media_item_id: media_item.id})
    end
  end

  @doc """
  Sets a media item aside, or puts it back.

  An allowlist of two fields rather than a changeset over whatever was sent, for the same
  reason the responses are explicit maps: the interface's own forms replace every field
  they carry, and forgetting one blanks it. That is a trap worth not rebuilding.

  Setting something aside always records why. Passing no reason gets a generic one rather
  than none, because a media item nothing will attempt again with no explanation is the
  defect this fork spent several commits removing.
  """
  def update_media_item(conn, %{"id" => id} = params) do
    media_item = Media.get_media_item!(id)

    case Media.update_media_item(media_item, set_aside_attrs(params)) do
      {:ok, media_item} ->
        json(conn, %{data: media_item_json(media_item)})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "invalid", details: changeset_errors(changeset)})
    end
  end

  defp set_aside_attrs(%{"prevent_download" => true} = params) do
    %{
      prevent_download: true,
      blocked_reason: params["blocked_reason"] || "Set aside via the API"
    }
  end

  defp set_aside_attrs(%{"prevent_download" => false}) do
    %{prevent_download: false, blocked_reason: nil}
  end

  defp set_aside_attrs(_params), do: %{}

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
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
