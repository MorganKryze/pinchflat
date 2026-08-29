defmodule Pinchflat.Repo.Migrations.AddManualQueueSwitches do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Both off, which is upstream's behaviour: nothing is stopped unless you stop it.
      #
      # Two switches rather than one because the two halves fail independently - a blocked
      # address kept indexing while it refused every download - so stopping both together
      # would throw away work that was still succeeding.
      add :indexing_paused, :boolean, default: false
      add :downloading_paused, :boolean, default: false
    end
  end
end
