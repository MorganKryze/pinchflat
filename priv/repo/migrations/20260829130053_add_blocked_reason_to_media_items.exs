defmodule Pinchflat.Repo.Migrations.AddBlockedReasonToMediaItems do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      # Why `prevent_download` was set. Distinct from `last_error`, which is cleared on the
      # next successful download: this one outlives the attempt that caused it, because
      # the whole point is to explain a media item that will never be attempted again.
      add :blocked_reason, :string
    end
  end
end
