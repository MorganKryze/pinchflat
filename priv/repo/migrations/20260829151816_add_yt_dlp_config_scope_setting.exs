defmodule Pinchflat.Repo.Migrations.AddYtDlpConfigScopeSetting do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      # Off by default. Upstream deliberately scopes the yt-dlp config cascade to
      # downloads, which is a defensible choice for options about output paths, and the
      # wrong one for a plugin directory or a player-client override.
      add :apply_yt_dlp_config_to_all_commands, :boolean, default: false
    end
  end
end
