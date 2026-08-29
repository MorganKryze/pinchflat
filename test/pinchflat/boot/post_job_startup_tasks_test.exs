defmodule Pinchflat.Boot.PostJobStartupTasksTest do
  use Pinchflat.DataCase

  alias Pinchflat.Settings
  alias Pinchflat.YoutubeStatus.Switches
  alias Pinchflat.Boot.PostJobStartupTasks

  describe "init/1" do
    test "puts back a pause the operator set before the restart" do
      Settings.set(indexing_paused: true)

      # Oban's pause is in memory and a restart wipes it, so without this the queue comes
      # back running while the setting still says it is stopped. The same disagreement
      # already caused a silent failure with the automatic backoff.
      assert {:ok, _state} = PostJobStartupTasks.init(%{})
      assert Switches.paused?(:indexing)
    end

    test "does nothing when no switch is off" do
      assert {:ok, _state} = PostJobStartupTasks.init(%{})

      refute Switches.any_paused?()
    end
  end
end
