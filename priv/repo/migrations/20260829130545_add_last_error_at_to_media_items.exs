defmodule Pinchflat.Repo.Migrations.AddLastErrorAtToMediaItems do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      # last_error survives until the next attempt, which can be days. Without a
      # timestamp the UI shows a stale message as though it were current.
      add :last_error_at, :utc_datetime
    end
  end
end
