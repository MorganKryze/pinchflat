defmodule PinchflatWeb.HealthController do
  use PinchflatWeb, :controller

  alias Pinchflat.Downloading.DownloadHealth

  @doc """
  Deliberately unchanged and deliberately dumb: it answers "the web server is up" and
  nothing more. Container health checks are pointed at it, and a probe that starts
  failing because downloads are throttled would restart a container that is working.
  """
  def check(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  @doc """
  What `check/2` refuses to know: whether anything is actually being downloaded.

  Every state here was previously only discoverable by opening the database by hand,
  which is a thing nobody does until they already suspect something.
  """
  def details(conn, params) do
    window_hours =
      case Integer.parse(params["window_hours"] || "1") do
        {hours, _} when hours > 0 and hours <= 168 -> hours
        _ -> 1
      end

    conn
    |> put_status(:ok)
    |> json(DownloadHealth.summary(window_hours))
  end
end
