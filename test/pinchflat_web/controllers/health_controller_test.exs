defmodule PinchflatWeb.HealthControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings

  describe "GET /healthcheck" do
    test "returns ok", %{conn: conn} do
      conn = get(conn, "/healthcheck")
      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "says nothing about downloads", %{conn: conn} do
      # Container health checks point here. A probe that went red because downloads were
      # throttled would restart a container that is working perfectly.
      conn = get(conn, "/healthcheck")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  describe "GET /healthcheck/details" do
    test "refuses without the route token", %{conn: conn} do
      conn = get(conn, "/healthcheck/details")

      assert response(conn, 401)
    end

    test "refuses with the wrong route token", %{conn: conn} do
      conn = get(conn, "/healthcheck/details?route_token=nope")

      assert response(conn, 401)
    end

    test "reports whether anything is getting downloaded", %{conn: conn} do
      media_item_fixture(%{media_filepath: nil, last_error: "nope", last_error_at: DateTime.utc_now()})

      conn = get(conn, "/healthcheck/details?route_token=#{Settings.get!(:route_token)}")
      body = json_response(conn, 200)

      assert body["failures_in_window"] == 1
      assert body["downloads_in_window"] == 0
      assert body["pending_without_job"] == 1
      assert body["last_successful_download_at"] == nil
    end

    test "says when the queues are stopped on purpose", %{conn: conn} do
      until = DateTime.utc_now() |> DateTime.add(20, :minute) |> DateTime.truncate(:second)
      Settings.set(download_backoff_paused_until: until)

      conn = get(conn, "/healthcheck/details?route_token=#{Settings.get!(:route_token)}")

      # Zero downloads in an hour means one thing if the queues are running and another
      # entirely if something stopped them deliberately.
      assert json_response(conn, 200)["queues_paused_until"]
    end

    test "accepts a wider window", %{conn: conn} do
      media_item_fixture(%{media_downloaded_at: DateTime.add(DateTime.utc_now(), -5, :hour)})

      token = Settings.get!(:route_token)

      assert json_response(get(conn, "/healthcheck/details?route_token=#{token}"), 200)["downloads_in_window"] == 0

      assert json_response(get(conn, "/healthcheck/details?route_token=#{token}&window_hours=24"), 200)[
               "downloads_in_window"
             ] == 1
    end

    test "falls back to an hour on a nonsense window", %{conn: conn} do
      token = Settings.get!(:route_token)

      conn = get(conn, "/healthcheck/details?route_token=#{token}&window_hours=banana")

      assert json_response(conn, 200)["window_hours"] == 1
    end
  end
end
