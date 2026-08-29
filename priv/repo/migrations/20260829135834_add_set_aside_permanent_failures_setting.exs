defmodule Pinchflat.Repo.Migrations.AddSetAsidePermanentFailuresSetting do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Off by default. Upstream reconsiders these at every index, which is a defensible
      # choice - a video can be un-privated, and an age restriction can be lifted - so
      # never looking again is opted into rather than inherited.
      add :set_aside_permanent_failures, :boolean, default: false
    end
  end
end
