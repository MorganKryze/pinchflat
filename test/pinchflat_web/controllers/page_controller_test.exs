defmodule PinchflatWeb.PageControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings

  describe "GET / when testing onboarding" do
    test "sets the onboarding setting to true when onboarding", %{conn: conn} do
      _conn = get(conn, ~p"/")
      assert Settings.get!(:onboarding)
    end

    test "displays the onboarding page when onboarding is forced", %{conn: conn} do
      Settings.set(onboarding: false)

      conn = get(conn, ~p"/?onboarding=1")
      assert html_response(conn, 200) =~ "Welcome to Pinchflat"
    end

    test "sets the onboarding setting to false if you pass the corrent query param", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert Settings.get!(:onboarding)

      _conn = get(conn, ~p"/?onboarding=0")
      refute Settings.get!(:onboarding)
    end

    test "displays the home page when not onboarding", %{conn: conn} do
      Settings.set(onboarding: false)

      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "MENU"
    end
  end

  describe "the needs-attention tile" do
    setup do
      Settings.set(onboarding: false)

      :ok
    end

    test "counts what is carrying a failure", %{conn: conn} do
      media_item_fixture(%{media_filepath: nil, last_error: "HTTP Error 500", last_error_at: DateTime.utc_now()})

      conn = get(conn, ~p"/")

      assert html_response(conn, 200) =~ "Needs Attention"
    end

    test "offers somewhere to go when there is trouble", %{conn: conn} do
      media_item =
        media_item_fixture(%{media_filepath: nil, last_error: "HTTP Error 500", last_error_at: DateTime.utc_now()})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)

      # A count with nowhere to click is a number, not a dashboard.
      assert html =~ "#tab-errors"
      assert html =~ media_item.title
    end
  end
end
