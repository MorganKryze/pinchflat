defmodule Pinchflat.Repo.Migrations.AddDownloadBackoffSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Off by default. This is the first thing in the fork that stops work on its own,
      # and an instance that has changed nothing should keep behaving as upstream does.
      add :download_backoff_enabled, :boolean, default: false
      add :download_backoff_threshold, :integer, default: 5
      add :download_backoff_minutes, :integer, default: 30
      # Not a setting - state, kept here so it is readable rather than hidden in a
      # process. Someone asking "why is nothing downloading" gets an answer with a time
      # on it.
      add :download_backoff_paused_until, :utc_datetime
    end
  end
end
