defmodule Pinchflat.Repo.Migrations.AddBackoffProbeSetting do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Off by default. Without it the pause ends when the clock says so, which is
      # upstream-shaped behaviour: nothing decides anything on its own.
      add :download_backoff_probe_enabled, :boolean, default: false
    end
  end
end
