defmodule Pinchflat.Repo.Migrations.AddNfoNamingOptionsToMediaProfiles do
  use Ecto.Migration

  def change do
    alter table(:media_profiles) do
      # Both off by default: they change what lands in the NFO, and upstream writes what
      # yt-dlp reports. Only affects the NFO - the title Pinchflat itself shows stays
      # whatever YouTube called it, because the interface should show what is really there.
      add :nfo_strip_uploader_from_title, :boolean, default: false
      add :nfo_strip_collection_suffix, :boolean, default: false
    end
  end
end
