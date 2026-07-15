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

  alias BeamicomPhx.Input
  alias Membrane.WebRTC.Live.Player

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        signaling = Membrane.WebRTC.Signaling.new()

        case Application.get_env(:beamicom_phx, :mode, :server) do
          # Client node: attach to the shared Relay, which links a WebRTC.Sink for
          # this browser and monitors us — it tears the sink down when we disconnect.
          :client ->
            BeamicomPhx.AV.Relay.add_browser(socket.id, self(), signaling)

          # Server node: start this browser's own encode pipeline (Phase 1), linked
          # to this LiveView so it dies with the socket.
          _server ->
            {:ok, _supervisor, _pipeline} =
              Membrane.Pipeline.start_link(BeamicomPhx.AV.Pipeline, egress_signaling: signaling)
        end

        Player.attach(socket, id: "videoPlayer", signaling: signaling)
      else
        socket
      end

    # The set of controller buttons currently held down; the NES controller is
    # stateful (each poll replaces the full set), so we track it and resend the
    # whole list on every change.
    {:ok, assign(socket, held: MapSet.new())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="game"
      phx-hook="PreventGameKeyScroll"
      phx-window-keydown="keydown"
      phx-window-keyup="keyup"
      class="crt-room"
    >
      <div class="crt">
        <div class="crt__cabinet">
          <div class="crt__bezel">
            <div class="crt__screen">
              <Player.live_render socket={@socket} player_id="videoPlayer" />
            </div>
          </div>
          <div class="crt__plate">
            <span class="crt__brand">BEAMICOM</span>
            <span class="crt__led" aria-hidden="true"></span>
          </div>
        </div>
      </div>
      <p class="crt__controls">
        Arrows = D-pad &nbsp;·&nbsp; X = A &nbsp;·&nbsp; Z = B &nbsp;·&nbsp; Enter = Start &nbsp;·&nbsp; Shift = Select
      </p>
    </div>
    """
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket),
    do: {:noreply, apply_key(socket, :down, key)}

  def handle_event("keyup", %{"key" => key}, socket),
    do: {:noreply, apply_key(socket, :up, key)}

  # Update the held-button set and push the full list to the emulator, but only
  # when the set actually changed (browsers fire keydown repeatedly while held).
  defp apply_key(socket, dir, key) do
    case Input.apply_key(socket.assigns.held, dir, key) do
      :ignore ->
        socket

      {held, buttons} ->
        if MapSet.equal?(held, socket.assigns.held) do
          socket
        else
          Input.press(1, buttons)
          assign(socket, held: held)
        end
    end
  end
end
