defmodule PinchflatWeb.PageControllerTest do
  use PinchflatWeb.ConnCase

  import Pinchflat.MediaFixtures

  alias Pinchflat.Settings

  describe "GET /youtube_status" do
    setup %{conn: _conn} do
      Settings.set(onboarding: false)
      :ok
    end

    test "reads grey when nothing has been attempted", %{conn: conn} do
      conn = get(conn, ~p"/youtube_status")
      response = html_response(conn, 200)

      assert response =~ "Nothing has been attempted"
      # A quiet instance is not a broken one, so nothing on the page claims trouble.
      refute response =~ "YouTube is refusing this address"
    end

    test "reads green once a download has got through", %{conn: conn} do
      media_item_fixture(%{
        media_downloaded_at: DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)
      })

      conn = get(conn, ~p"/youtube_status")

      assert html_response(conn, 200) =~ "Downloads are getting through"
    end

    test "says downloads are refused while indexing still answers", %{conn: conn} do
      media_item_fixture(%{
        last_error: "Sign in to confirm you're not a bot",
        last_error_at: DateTime.utc_now() |> DateTime.add(-5, :minute) |> DateTime.truncate(:second)
      })

      conn = get(conn, ~p"/youtube_status")
      response = html_response(conn, 200)

      assert response =~ "Indexing works, downloads do not"
      assert response =~ "1 throttled"
    end

    test "draws a segment for every part of the day, measured or not", %{conn: conn} do
      conn = get(conn, ~p"/youtube_status")

      # 96 quarter-hour segments, all of them unmeasured on a fresh instance. A bar drawn
      # only from the samples that exist would show a full day of nothing wrong.
      assert length(String.split(html_response(conn, 200), "nothing was measuring")) == 97
    end
  end

  describe "POST /youtube_status/:switch/:action" do
    setup do
      Settings.set(onboarding: false)
      :ok
    end

    test "stops indexing and says so", %{conn: conn} do
      conn = post(conn, ~p"/youtube_status/indexing/pause")

      assert redirected_to(conn) == ~p"/youtube_status"
      assert Pinchflat.YoutubeStatus.Switches.paused?(:indexing)
    end

    test "starts it again", %{conn: conn} do
      Pinchflat.YoutubeStatus.Switches.set(:downloading, true)

      conn = post(conn, ~p"/youtube_status/downloading/resume")

      refute Pinchflat.YoutubeStatus.Switches.paused?(:downloading)
      assert redirected_to(conn) == ~p"/youtube_status"
    end

    test "refuses a switch nobody defined", %{conn: conn} do
      # The path parameter is mapped, never converted, so a made-up name cannot reach an
      # atom or a queue.
      conn = post(conn, ~p"/youtube_status/media_fetching/pause")

      assert redirected_to(conn) == ~p"/youtube_status"
      refute Pinchflat.YoutubeStatus.Switches.any_paused?()
    end

    test "says which half is stopped rather than reporting the queues as running", %{conn: conn} do
      post(conn, ~p"/youtube_status/downloading/pause")

      # "running" here would be answering the wrong question: three different things stop
      # these queues and only one of them lifts itself.
      response = html_response(get(conn, ~p"/youtube_status"), 200)

      assert response =~ "downloading stopped by hand"
      refute response =~ ">\n            running"
    end

    test "the page then reads blue and offers to start it", %{conn: conn} do
      post(conn, ~p"/youtube_status/downloading/pause")

      response = html_response(get(conn, ~p"/youtube_status"), 200)

      assert response =~ "Stopped on purpose"
      assert response =~ "Start"
    end
  end

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
