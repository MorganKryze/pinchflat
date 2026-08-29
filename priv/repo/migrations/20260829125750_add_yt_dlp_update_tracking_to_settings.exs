defmodule Pinchflat.Repo.Migrations.AddYtDlpUpdateTrackingToSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :yt_dlp_last_update_attempted_at, :utc_datetime
      # nil means the last attempt succeeded. The output of a failed one is kept here
      # rather than only logged, so the reason survives a log rotation.
      add :yt_dlp_last_update_error, :string
    end
  end
end
