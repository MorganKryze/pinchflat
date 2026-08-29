defmodule Pinchflat.Repo.Migrations.AddNfoDescriptionOptionsToMediaProfiles do
  use Ecto.Migration

  def change do
    alter table(:media_profiles) do
      # Both off by default. A YouTube description is mostly links, subscription pleas and
      # pointers to other videos, but upstream writing it verbatim is what yt-dlp reported
      # and is a defensible thing to do.
      add :nfo_strip_urls_from_description, :boolean, default: false
      # nil means no cap.
      add :nfo_description_max_length, :integer
    end
  end
end
