defmodule Pinchflat.Repo.Migrations.AddDownloadRetrySettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # How hard to keep trying a download that failed. Both are read when the job runs
      # rather than when it is compiled, so changing them takes effect on the next
      # attempt without a restart.
      add :download_max_attempts, :integer, default: 5
      add :download_retry_backoff_base_seconds, :integer, default: 30
    end
  end
end
