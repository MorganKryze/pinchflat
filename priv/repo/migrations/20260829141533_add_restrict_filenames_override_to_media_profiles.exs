defmodule Pinchflat.Repo.Migrations.AddRestrictFilenamesOverrideToMediaProfiles do
  use Ecto.Migration

  def change do
    alter table(:media_profiles) do
      # Three states rather than a boolean, because "inherit" is a real answer and a
      # boolean cannot say it. Defaults to inherit, so nothing changes for a profile
      # nobody has touched and the global setting keeps meaning what it meant.
      add :restrict_filenames_override, :string, default: "inherit"
    end
  end
end
