defmodule PinchflatWeb.Api.ApiControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures
  import Pinchflat.SourcesFixtures

  alias Pinchflat.Settings
  alias Pinchflat.Downloading.MediaDownloadWorker

  defp token, do: Settings.get!(:route_token)

  describe "authentication" do
    test "every route refuses without the token", %{conn: conn} do
      source = source_fixture()

      for path <- ["/api/v1/sources", "/api/v1/sources/#{source.id}", "/api/v1/sources/#{source.id}/media"] do
        assert response(get(conn, path), 401)
      end
    end

    test "refuses a wrong token", %{conn: conn} do
      assert response(get(conn, "/api/v1/sources?route_token=nope"), 401)
    end
  end

  describe "GET /api/v1/sources" do
    test "lists every source, not a page of ten", %{conn: conn} do
      # The whole reason this exists: /sources is a LiveView that pages ten at a time over
      # a websocket, so enumerating sources meant walking ids until enough 404s came back.
      for _ <- 1..12, do: source_fixture()

      conn = get(conn, "/api/v1/sources?route_token=#{token()}")

      assert length(json_response(conn, 200)["data"]) == 12
    end

    test "publishes only the fields it means to", %{conn: conn} do
      source_fixture()

      conn = get(conn, "/api/v1/sources?route_token=#{token()}")
      [source] = json_response(conn, 200)["data"]

      # Built from an explicit map rather than by encoding the schema, so adding a column
      # cannot quietly publish it.
      assert Map.has_key?(source, "custom_name")
      refute Map.has_key?(source, "inserted_at")
    end
  end

  describe "GET /api/v1/sources/:source_id/media" do
    setup do
      source = source_fixture()

      downloaded = media_item_fixture(source_id: source.id, media_downloaded_at: DateTime.utc_now())

      errored =
        media_item_fixture(
          source_id: source.id,
          media_filepath: nil,
          last_error: "HTTP Error 500",
          last_error_at: DateTime.utc_now()
        )

      {:ok, %{source: source, downloaded: downloaded, errored: errored}}
    end

    test "narrows to a state", %{conn: conn, source: source, errored: errored} do
      conn = get(conn, "/api/v1/sources/#{source.id}/media?state=errored&route_token=#{token()}")

      assert [%{"id" => id}] = json_response(conn, 200)["data"]
      assert id == errored.id
    end

    test "returns everything for an unrecognised state", %{conn: conn, source: source} do
      # Returning nothing would look exactly like a source with no media, and a script
      # cannot tell those apart.
      conn = get(conn, "/api/v1/sources/#{source.id}/media?state=banana&route_token=#{token()}")

      assert length(json_response(conn, 200)["data"]) == 2
    end

    test "carries the failure and the reason", %{conn: conn, source: source} do
      conn = get(conn, "/api/v1/sources/#{source.id}/media?state=errored&route_token=#{token()}")
      [item] = json_response(conn, 200)["data"]

      assert item["last_error"] == "HTTP Error 500"
      assert item["last_error_at"]
      assert Map.has_key?(item, "blocked_reason")
    end

    test "pages", %{conn: conn, source: source} do
      conn = get(conn, "/api/v1/sources/#{source.id}/media?limit=1&route_token=#{token()}")
      body = json_response(conn, 200)

      assert length(body["data"]) == 1
      assert body["limit"] == 1
    end

    test "caps the limit rather than refusing it", %{conn: conn, source: source} do
      conn = get(conn, "/api/v1/sources/#{source.id}/media?limit=99999&route_token=#{token()}")

      assert json_response(conn, 200)["limit"] == 500
    end

    test "ignores a nonsense limit", %{conn: conn, source: source} do
      conn = get(conn, "/api/v1/sources/#{source.id}/media?limit=banana&route_token=#{token()}")

      assert json_response(conn, 200)["limit"] == 100
    end
  end

  describe "GET /api/v1/media/:id" do
    test "returns one media item", %{conn: conn} do
      media_item = media_item_fixture()

      conn = get(conn, "/api/v1/media/#{media_item.id}?route_token=#{token()}")

      assert json_response(conn, 200)["data"]["title"] == media_item.title
    end
  end

  describe "POST /api/v1/sources/:source_id/downloads" do
    test "queues everything pending", %{conn: conn} do
      source = source_fixture()
      _media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      assert [] = all_enqueued(worker: MediaDownloadWorker)

      conn = post(conn, "/api/v1/sources/#{source.id}/downloads?route_token=#{token()}")

      assert json_response(conn, 200)["data"]["queued"]
      assert [_] = all_enqueued(worker: MediaDownloadWorker)
    end

    test "asking twice does not queue twice", %{conn: conn} do
      source = source_fixture()
      _media_item = media_item_fixture(source_id: source.id, media_filepath: nil)

      post(conn, "/api/v1/sources/#{source.id}/downloads?route_token=#{token()}")
      post(conn, "/api/v1/sources/#{source.id}/downloads?route_token=#{token()}")

      # The worker's uniqueness already guarantees this. Worth a test because a retry
      # script that doubles the queue every time it runs is worse than no script.
      assert [_only_one] = all_enqueued(worker: MediaDownloadWorker)
    end

    test "refuses without the token", %{conn: conn} do
      source = source_fixture()

      assert response(post(conn, "/api/v1/sources/#{source.id}/downloads"), 401)
    end
  end

  describe "POST /api/v1/media/:media_item_id/downloads" do
    test "queues one media item", %{conn: conn} do
      media_item = media_item_fixture(media_filepath: nil)

      conn = post(conn, "/api/v1/media/#{media_item.id}/downloads?route_token=#{token()}")

      assert json_response(conn, 200)["data"]["queued"]
      assert [_] = all_enqueued(worker: MediaDownloadWorker)
    end

    test "says so rather than pretending when it will not download", %{conn: conn} do
      media_item = media_item_fixture(media_filepath: nil, prevent_download: true)

      conn = post(conn, "/api/v1/media/#{media_item.id}/downloads?route_token=#{token()}")

      # A script that asked for a download and got a 200 is entitled to believe one is
      # coming.
      assert json_response(conn, 409)["error"] =~ "not pending"
      assert [] = all_enqueued(worker: MediaDownloadWorker)
    end
  end

  describe "PATCH /api/v1/media/:id" do
    test "sets a media item aside", %{conn: conn} do
      media_item = media_item_fixture()

      conn =
        patch(conn, "/api/v1/media/#{media_item.id}?route_token=#{token()}", %{
          "prevent_download" => true,
          "blocked_reason" => "Deleted upstream"
        })

      body = json_response(conn, 200)["data"]

      assert body["prevent_download"]
      assert body["blocked_reason"] == "Deleted upstream"
    end

    test "records a reason even when none was given", %{conn: conn} do
      media_item = media_item_fixture()

      conn = patch(conn, "/api/v1/media/#{media_item.id}?route_token=#{token()}", %{"prevent_download" => true})

      # A media item nothing will attempt again with no explanation is the defect this
      # fork spent several commits removing. The API does not get to reintroduce it.
      assert json_response(conn, 200)["data"]["blocked_reason"] == "Set aside via the API"
    end

    test "puts one back, clearing the reason with it", %{conn: conn} do
      media_item = media_item_fixture(prevent_download: true, blocked_reason: "Age restricted")

      conn = patch(conn, "/api/v1/media/#{media_item.id}?route_token=#{token()}", %{"prevent_download" => false})

      body = json_response(conn, 200)["data"]

      refute body["prevent_download"]
      refute body["blocked_reason"]
    end

    test "ignores fields it was not asked to change", %{conn: conn} do
      media_item = media_item_fixture(title: "Original")

      patch(conn, "/api/v1/media/#{media_item.id}?route_token=#{token()}", %{
        "prevent_download" => true,
        "title" => "Rewritten"
      })

      # An allowlist rather than a changeset over whatever was sent. The interface's own
      # forms replace every field they carry and blank the ones you forget; that is a
      # trap worth not rebuilding.
      assert Pinchflat.Media.get_media_item!(media_item.id).title == "Original"
    end
  end
end
