defmodule Pinchflat.Boot.PreJobStartupTasks do
  @moduledoc """
  This module is responsible for running startup tasks on app boot
  BEFORE the job runner has initiallized.

  It's a GenServer because that plays REALLY nicely with the existing
  Phoenix supervision tree.
  """

  # restart: :temporary means that this process will never be restarted (ie: will run once and then die)
  use GenServer, restart: :temporary
  import Ecto.Query, warn: false
  require Logger

  alias Pinchflat.Repo
  alias Pinchflat.Settings
  alias Pinchflat.Utils.FilesystemUtils
  alias Pinchflat.Downloading.ResumeQueuesWorker

  alias Pinchflat.Lifecycle.UserScripts.CommandRunner, as: UserScriptRunner

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{env: Application.get_env(:pinchflat, :env)}, opts)
  end

  @doc """
  Runs application startup tasks.

  Any code defined here will run every time the application starts. You must
  make sure that the code is idempotent and safe to run multiple times.

  This is a good place to set up default settings, create initial records, stuff like that.
  Should be fast - anything with the potential to be slow should be kicked off as a job instead.
  """
  @impl true
  def init(%{env: :test} = state) do
    # Do nothing _as part of the app bootup process_.
    # Since bootup calls `start_link` and that's where the `env` state is injected,
    # you can still call `.init()` manually to run these tasks for testing purposes
    {:ok, state}
  end

  def init(state) do
    ensure_tmpfile_directory()
    reset_executing_jobs()
    clear_stale_queue_pause()
    create_blank_yt_dlp_files()
    create_blank_user_script_file()
    apply_default_settings()
    run_app_init_script()

    {:ok, state}
  end

  defp ensure_tmpfile_directory do
    tmpfile_dir = Application.get_env(:pinchflat, :tmpfile_directory)

    if !File.exists?(tmpfile_dir) do
      File.mkdir_p!(tmpfile_dir)
    end
  end

  # If a node cannot gracefully shut down, the currently executing jobs get stuck
  # in the "executing" state. This is a problem because the job runner will not
  # pick them up again
  defp reset_executing_jobs do
    {count, _} =
      Oban.Job
      |> where(state: "executing")
      |> Repo.update_all(set: [state: "retryable"])

    Logger.info("Reset #{count} executing jobs")
  end

  # Oban's queue pause lives in memory and does not survive a restart, while the setting
  # recording it does. Left alone, the two disagree: the queues come back running and the
  # backoff believes they are still stopped, so it declines to stop them again for the
  # rest of the window - downloading against a blocked address with the protection
  # silently switched off. Anything that restarts a container mid-block hits this every
  # time, which includes any watchdog built to restart it during exactly that.
  #
  # Cleared rather than re-applied: a restart is a fresh start. If the block is still
  # there, the next refusals trip the threshold again within minutes, and the failures
  # that would trip it are already recorded.
  #
  # The scheduled resume goes with it, and that is not tidiness. Left in flight it runs
  # against queues that are no longer paused, probes, and writes a new pause - while a
  # throttled download, free to run because the pause was just cleared, has already
  # scheduled a resume of its own. Whichever wrote the setting last is the one Oban's
  # uniqueness silently drops. Measured on a real instance: the setting said 13:30 and the
  # queues came back at 12:54.
  defp clear_stale_queue_pause do
    case Settings.get!(:download_backoff_paused_until) do
      nil ->
        :ok

      until ->
        Logger.info("Clearing a queue pause that was set to last until #{until}: a restart resets it")
        Settings.set(download_backoff_paused_until: nil)
        Settings.set(download_backoff_extensions: 0)

        case ResumeQueuesWorker.cancel_pending() do
          0 -> :ok
          count -> Logger.info("Cancelled #{count} scheduled resume(s) left over from before the restart")
        end
    end
  end

  defp create_blank_yt_dlp_files do
    files = ["cookies.txt", "yt-dlp-configs/base-config.txt"]
    base_dir = Application.get_env(:pinchflat, :extras_directory)

    Enum.each(files, fn file ->
      filepath = Path.join(base_dir, file)

      if !File.exists?(filepath) do
        Logger.info("Creating blank file: #{filepath}")

        FilesystemUtils.write_p!(filepath, "")
      end
    end)
  end

  defp create_blank_user_script_file do
    base_dir = Application.get_env(:pinchflat, :extras_directory)
    filepath = Path.join([base_dir, "user-scripts", "lifecycle"])

    if !File.exists?(filepath) do
      Logger.info("Creating blank file and making it executable: #{filepath}")

      FilesystemUtils.write_p!(filepath, "")
      File.chmod(filepath, 0o755)
    end
  end

  defp apply_default_settings do
    {:ok, yt_dlp_version} = yt_dlp_runner().version()
    {:ok, apprise_version} = apprise_runner().version()

    Settings.set(yt_dlp_version: yt_dlp_version)
    Settings.set(apprise_version: apprise_version)
  end

  defp run_app_init_script do
    runner = Application.get_env(:pinchflat, :user_script_runner, UserScriptRunner)

    runner.run(:app_init, %{})
  end

  defp yt_dlp_runner do
    Application.get_env(:pinchflat, :yt_dlp_runner)
  end

  defp apprise_runner do
    Application.get_env(:pinchflat, :apprise_runner)
  end
end
