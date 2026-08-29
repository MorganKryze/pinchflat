defmodule Pinchflat.Repo.Migrations.AlignDownloadDefaultsWithUpstream do
  use Ecto.Migration

  def up do
    alter table(:settings) do
      # Priority for a forced retry. 5 is what upstream inserts, and is the worker's own
      # default; 0 jumps the queue. A preference, so it gets a setting rather than being
      # decided here.
      add :forced_download_priority, :integer, default: 5
    end

    # These two shipped with values this fork chose. The fork's rule is that upstream
    # behaviour is the default and anything else is opted into, so they move back:
    # 20 attempts is Oban's default, which is what upstream gets by not setting one, and
    # a null backoff base means Oban's own backoff rather than this fork's curve.
    #
    # Only rows still holding the values this fork shipped are touched. Anything else is
    # a deliberate choice and is left alone.
    execute "UPDATE settings SET download_max_attempts = 20 WHERE download_max_attempts = 5;"

    execute "UPDATE settings SET download_retry_backoff_base_seconds = NULL WHERE download_retry_backoff_base_seconds = 30;"
  end

  def down do
    alter table(:settings) do
      remove :forced_download_priority
    end

    # Restores the values this migration replaced, for the case where only this one is
    # rolled back. Rolling back further removes these columns anyway, but a half-rolled
    # back database that silently kept the new defaults would be a nasty thing to debug.
    execute "UPDATE settings SET download_max_attempts = 5 WHERE download_max_attempts = 20;"

    execute "UPDATE settings SET download_retry_backoff_base_seconds = 30 WHERE download_retry_backoff_base_seconds IS NULL;"
  end
end
