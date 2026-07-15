defmodule BeamicomPhx.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BeamicomPhxWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:beamicom_phx, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BeamicomPhx.PubSub},
        BeamicomPhxWeb.Endpoint
      ] ++ emulator_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BeamicomPhx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # server mode + a ROM path => run the emulator. Beamicom.NES.Output is already
  # started by the :beamicom application. Runtime produces frames/audio into it.
  defp emulator_children do
    mode = Application.get_env(:beamicom_phx, :mode, :server)
    rom = Application.get_env(:beamicom_phx, :rom)

    cond do
      mode == :server and is_binary(rom) ->
        [{Beamicom.NES.Runtime, rom: rom}]

      mode == :server ->
        require Logger
        Logger.warning("BEAMICOM_MODE=server but BEAMICOM_ROM is unset; emulator not started")
        []

      true ->
        []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BeamicomPhxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
