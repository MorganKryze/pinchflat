defmodule Pinchflat.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :pinchflat

  # The FIRST migration this fork added, not the last upstream one. Ecto's `:to` is
  # inclusive in both directions, so rolling back "to" the last upstream migration would
  # take that one down with it - which on a first attempt quietly removed upstream's own
  # restrict_filenames column. Rolling back to this one stops exactly at the boundary.
  @first_fork_migration 20_260_829_125_750

  require Logger

  alias Pinchflat.Utils.FilesystemUtils

  @doc """
  Runs pending migrations, taking a copy of the database first if there are any.

  A migration that adds a column cannot lose data, but going back to an older image is
  not automatic once one has run, and finding that out on a library you care about is a
  bad time to find it out. The copy costs a few seconds on an upgrade and nothing on a
  boot with nothing pending.

  Returns :ok
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          case Ecto.Migrator.migrations(repo) |> Enum.filter(fn {status, _, _} -> status == :down end) do
            [] ->
              Logger.info("No pending migrations")

            pending ->
              Logger.info("#{length(pending)} pending migration(s)")
              backup_database(repo)
          end

          Ecto.Migrator.run(repo, :up, all: true)
        end)
    end

    :ok
  end

  @doc """
  Rolls back to a migration version, which is how you produce a database an older image
  can open.

  Every migration this fork adds only adds columns, so rolling them back removes those
  columns and the rows they held. Nothing upstream wrote is touched. Pass the last
  version the older image knows about.

  Returns :ok
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  @doc """
  Rolls back everything this fork added, leaving a database the upstream image can open.

  Takes a copy first, under a different name from the one `migrate/0` writes, so running
  this does not overwrite the snapshot taken on the way up.

  Returns :ok
  """
  def rollback_fork_migrations do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn repo ->
          backup_database(repo, "pre-rollback")

          Ecto.Migrator.run(repo, :down, to: @first_fork_migration)
        end)
    end

    :ok
  end

  # VACUUM INTO rather than a file copy: the database runs in WAL mode, so the file on
  # disk is not the whole story and copying it can catch a partial write. This asks SQLite
  # for a consistent single-file snapshot instead, whatever state the WAL is in.
  defp backup_database(repo, label \\ "pre-migration") do
    if System.get_env("SKIP_MIGRATION_BACKUP") in [nil, ""] do
      write_backup(repo, label)
    else
      Logger.warning("SKIP_MIGRATION_BACKUP is set, migrating without a copy of the database")
    end
  end

  defp write_backup(repo, label) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    path = Path.join(database_directory(repo), "pinchflat.#{label}-#{stamp}.db")

    Logger.info("Backing up the database to #{path}")

    case repo.query("VACUUM INTO ?", [path]) do
      {:ok, _} ->
        Logger.info("Backup written. Delete it once the upgrade has proven itself")

      {:error, error} ->
        # Loud, and fatal. Migrating without the copy the operator was told they would get
        # is worse than not migrating.
        # A copy needs as much free space as the database uses, so the realistic cause is
        # a full disk. Refusing to migrate is the right default, but a container that will
        # not boot and offers no way out is not - hence the escape hatch, named in the
        # message so nobody has to go looking for it.
        Logger.error("""
        Could not back up the database before migrating: #{inspect(error)}

        The most likely cause is not enough free space next to the database, since the
        copy needs roughly as much room as the database itself.

        Free some space, or set SKIP_MIGRATION_BACKUP=1 to migrate without a copy. If you
        take that route, copy the database yourself first.
        """)

        raise "Database backup failed, refusing to migrate"
    end
  end

  defp database_directory(repo) do
    repo.config() |> Keyword.fetch!(:database) |> Path.dirname()
  end

  def check_file_permissions do
    load_app()

    directories =
      [
        "/config",
        "/downloads",
        "/etc/yt-dlp",
        "/etc/yt-dlp/plugins",
        Application.get_env(:pinchflat, :media_directory),
        Application.get_env(:pinchflat, :tmpfile_directory),
        Application.get_env(:pinchflat, :extras_directory),
        Application.get_env(:pinchflat, :metadata_directory),
        Application.get_env(:tzdata, :data_dir)
      ]
      |> Enum.uniq()
      |> Enum.filter(&(&1 != nil))

    Enum.each(directories, fn dir ->
      Logger.info("Checking permissions for #{dir}")
      filepath = Path.join([dir, ".keep"])

      case FilesystemUtils.write_p(filepath, "") do
        :ok ->
          Logger.info("Permissions OK")

        {:error, :eacces} ->
          Logger.error(permission_denied_screed(dir))
          raise "Permission denied"

        err ->
          Logger.error("Permissions check failed: #{inspect(err)}")
          raise "Unknown error"
      end
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  defp permission_denied_screed(dir) do
    """
    The directory "#{dir}" is not writeable by the Docker container.

    Please ensure that the directory exists and is writeable by the Docker
    container. All setups are different, but you may be able to run something
    like this on the *host*:

      chown nobody -R <host path that maps to #{dir}>
      chmod 755 -R <host path that maps to #{dir}>

    Swapping in your real host path. Then, you should set the user running
    this container by editing your `docker run` command like so:

        docker run --user 99:100 <rest of the command>

    Or adding `user: '99:100'` to the Pinchflat service of your Docker Compose
    file. Again, there are many ways to do this depending on your setup and
    this is just one example. See issue #106 in the Pinchflat Github for more.

    No matter the case, this _is_ a permissions error and allowing the container
    to write to the directory is the only way to fix it. It is not recommended
    to run the container as `root` because files created by Pinchflat may not
    be accessible to other apps that want to modify them.
    """
  end
end
