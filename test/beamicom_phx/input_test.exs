defmodule BeamicomPhx.InputTest do
  use ExUnit.Case, async: true

  alias BeamicomPhx.Input

  describe "button_for/1" do
    test "maps arrow keys to the d-pad" do
      assert Input.button_for("ArrowUp") == :up
      assert Input.button_for("ArrowDown") == :down
      assert Input.button_for("ArrowLeft") == :left
      assert Input.button_for("ArrowRight") == :right
    end

    test "maps action/menu keys (case-insensitive for letters)" do
      assert Input.button_for("x") == :a
      assert Input.button_for("X") == :a
      assert Input.button_for("z") == :b
      assert Input.button_for("Z") == :b
      assert Input.button_for("Enter") == :start
      assert Input.button_for("Shift") == :select
    end

    test "returns nil for unmapped keys" do
      assert Input.button_for("q") == nil
      assert Input.button_for("F5") == nil
      assert Input.button_for(" ") == nil
    end
  end

  describe "press/2" do
    test "is a no-op (returns :ok) when no local Runtime is running" do
      # In the test env the emulator Runtime is not started; press must not crash.
      refute Process.whereis(Beamicom.NES.Runtime)
      assert Input.press(1, [:a, :start]) == :ok
    end
  end
end
