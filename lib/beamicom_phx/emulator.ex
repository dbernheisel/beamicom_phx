defmodule BeamicomPhx.Emulator do
  @moduledoc """
  Manages the lifecycle of the single NES `Beamicom.NES.Runtime` so a ROM can be
  (re)loaded at runtime — e.g. dropped into the browser.

  The `Runtime` runs under a `DynamicSupervisor` (this module's registered name).
  Swapping ROMs stops the current `Runtime` and starts a new one; because both
  publish into the shared `Beamicom.NES.Output`, the A/V pipelines and every
  connected browser pick up the new game with no restart.

  `use`d as a supervision child (`BeamicomPhx.Emulator`), it starts the
  `DynamicSupervisor`. `load/1` is then called at boot (env ROM) or from the
  LiveView when a ROM is uploaded.
  """
  @sup __MODULE__

  def child_spec(_arg) do
    %{
      id: @sup,
      start: {DynamicSupervisor, :start_link, [[name: @sup, strategy: :one_for_one]]},
      type: :supervisor
    }
  end

  @doc "Stop any running Runtime and start a new one for `rom_path`."
  def load(rom_path) when is_binary(rom_path) do
    _ = stop()

    case DynamicSupervisor.start_child(@sup, {Beamicom.NES.Runtime, rom: rom_path}) do
      {:ok, _pid} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop the running Runtime, if any."
  def stop do
    case Process.whereis(Beamicom.NES.Runtime) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@sup, pid)
    end
  end

  @doc "Whether a Runtime is currently loaded."
  def loaded?, do: is_pid(Process.whereis(Beamicom.NES.Runtime))
end
