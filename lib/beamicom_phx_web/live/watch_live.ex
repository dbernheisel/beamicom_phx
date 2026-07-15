defmodule BeamicomPhxWeb.WatchLive do
  @moduledoc """
  Watch page: one WebRTC-streamed view of the server's running game. On the
  connected mount it creates a shared `Membrane.WebRTC.Signaling`, starts a
  linked A/V pipeline whose `WebRTC.Sink` uses that signaling, and attaches the
  `Live.Player` (which uses the same signaling) — so browser and Sink negotiate
  over the LiveView socket. The pipeline is linked to this process, so it is torn
  down automatically when the browser disconnects.
  """
  use BeamicomPhxWeb, :live_view

  alias Membrane.WebRTC.Live.Player

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        signaling = Membrane.WebRTC.Signaling.new()

        {:ok, _supervisor, _pipeline} =
          Membrane.Pipeline.start_link(BeamicomPhx.AV.Pipeline, egress_signaling: signaling)

        Player.attach(socket, id: "videoPlayer", signaling: signaling)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <h1 class="text-xl font-bold mb-4">Beamicom</h1>
      <Player.live_render socket={@socket} player_id="videoPlayer" />
    </div>
    """
  end
end
