defmodule Pinchflat.Repo.Migrations.CreateYoutubeStatusSamples do
  use Ecto.Migration

  def change do
    # One row per sampling window, so the interface can draw a history rather than a
    # single reading. Nothing else keeps a history: `media_items` holds only the *last*
    # error, and `oban_jobs` are pruned. A block that cleared overnight leaves no trace
    # anywhere without this table.
    create table(:youtube_status_samples) do
      add :state, :string, null: false
      # The counts that produced the state, so a segment of the history bar can explain
      # itself without recomputing a window whose source rows may be gone.
      add :downloads, :integer, null: false, default: 0
      add :download_failures, :integer, null: false, default: 0
      # Refusals that could be YouTube refusing this address rather than a verdict on one
      # video, and the subset of those carrying the explicit throttle message. Both are
      # kept because the difference is the open question: a block presented itself as an
      # unnamed error at one tier and as an explicit throttle at another.
      add :connection_failures, :integer, null: false, default: 0
      add :throttle_failures, :integer, null: false, default: 0
      add :indexing_successes, :integer, null: false, default: 0
      add :indexing_failures, :integer, null: false, default: 0
      # How far back the counts reach. Stored because the sampler covers the gap since the
      # previous sample, which is longer than the usual interval after a restart.
      add :window_seconds, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:youtube_status_samples, [:inserted_at])
  end
end
