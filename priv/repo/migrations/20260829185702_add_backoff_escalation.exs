defmodule Pinchflat.Repo.Migrations.AddBackoffEscalation do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # On by default, unlike everything else this fork adds, because it only does
      # anything once the probe is turned on - and someone who has opted into asking
      # YouTube whether a block has cleared wants the discreet version of that by default.
      # Turn it off to get back the fixed interval, which recovers sooner and asks more.
      add :download_backoff_escalate, :boolean, default: true
      # State, like `download_backoff_paused_until`: how many times in a row the probe has
      # come back refused. Reset by a probe that answers, and by a restart.
      add :download_backoff_extensions, :integer, default: 0
    end
  end
end
