defmodule PinchflatWeb.Pages.PageController do
  use PinchflatWeb, :controller
  use Pinchflat.Media.MediaQuery

  alias Pinchflat.Repo
  alias Pinchflat.Sources.Source
  alias Pinchflat.YoutubeStatus
  alias Pinchflat.Profiles.MediaProfile
  alias Pinchflat.YoutubeStatus.Switches
  alias Pinchflat.Downloading.DownloadHealth
  alias Pinchflat.Downloading.DownloadBackoff

  # What each colour claims, said once so the page and the tests read the same list.
  @legend [
    nominal: "downloads getting through",
    degraded: "indexing works, downloads refused",
    blocked: "both refused",
    idle: "nothing attempted",
    disabled: "stopped on purpose",
    no_data: "nothing measuring"
  ]

  # Mapped rather than converted, so a made-up path parameter cannot reach an atom or a
  # queue name.
  @switch_names %{"indexing" => :indexing, "downloading" => :downloading}
  @switch_actions %{"pause" => true, "resume" => false}
  @switch_labels %{indexing: "Indexing", downloading: "Downloading"}

  # Same reason as the switches: a query string is user input, so it is mapped to a known
  # range rather than converted to whatever atom it spells.
  @range_names %{"hour" => :hour, "day" => :day, "week" => :week, "month" => :month}

  def home(conn, params) do
    done_onboarding = params["onboarding"] == "0"
    force_onboarding = params["onboarding"] == "1"

    if done_onboarding, do: Settings.set(onboarding: false)

    if force_onboarding || Settings.get!(:onboarding) do
      render_onboarding_page(conn)
    else
      render_home_page(conn)
    end
  end

  def youtube_status(conn, params) do
    range = Map.get(@range_names, params["range"], :day)

    render(conn, :youtube_status,
      # The headline reads an hour whatever the history is set to. It answers "what is
      # happening now", and a month of averages answers something else.
      current: YoutubeStatus.current(),
      range: range,
      ranges: YoutubeStatus.ranges(),
      buckets: YoutubeStatus.history_buckets_for(range),
      health: DownloadHealth.summary(24),
      switches: switch_states(),
      legend: @legend
    )
  end

  def youtube_status_switch(conn, %{"switch" => switch, "action" => action}) do
    case {Map.fetch(@switch_names, switch), Map.fetch(@switch_actions, action)} do
      {{:ok, name}, {:ok, paused?}} ->
        Switches.set(name, paused?)

        conn
        |> put_flash(:info, "#{@switch_labels[name]} #{if paused?, do: "stopped", else: "started"}")
        |> redirect(to: ~p"/youtube_status")

      _ ->
        conn
        |> put_flash(:error, "No such switch")
        |> redirect(to: ~p"/youtube_status")
    end
  end

  defp switch_states do
    # The backoff holds every one of these queues too, and it is not a switch. A row that
    # reported only the switch said "running" while Oban had the queue stopped.
    backoff_until = DownloadBackoff.paused_until()

    Enum.map(Switches.names(), fn name ->
      %{
        name: name,
        label: @switch_labels[name],
        paused: Switches.paused?(name),
        backoff_until: backoff_until
      }
    end)
  end

  defp render_home_page(conn) do
    downloaded_media_items = where(MediaQuery.new(), ^MediaQuery.downloaded())

    conn
    |> render(:home,
      media_profile_count: Repo.aggregate(MediaProfile, :count, :id),
      source_count: Repo.aggregate(Source, :count, :id),
      media_item_size: Repo.aggregate(downloaded_media_items, :sum, :media_size_bytes),
      media_item_count: Repo.aggregate(downloaded_media_items, :count, :id),
      # The dashboard counted four kinds of success and no kind of trouble, so a library
      # quietly losing media looked exactly like one that was fine.
      errored_count: Repo.aggregate(where(MediaQuery.new(), ^MediaQuery.errored()), :count, :id)
    )
  end

  defp render_onboarding_page(conn) do
    Settings.set(onboarding: true)

    conn
    |> render(:onboarding_checklist,
      media_profiles_exist: Repo.exists?(MediaProfile),
      sources_exist: Repo.exists?(Source),
      layout: {Layouts, :onboarding}
    )
  end
end
