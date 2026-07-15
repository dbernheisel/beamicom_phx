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

        {:ok, _supervisor, _pipeline} =
          Membrane.Pipeline.start_link(BeamicomPhx.AV.Pipeline, egress_signaling: signaling)

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
      class="p-4"
    >
      <h1 class="text-xl font-bold mb-4">Beamicom</h1>
      <Player.live_render socket={@socket} player_id="videoPlayer" />
      <p class="mt-4 text-sm opacity-70">
        Arrows = D-pad · X = A · Z = B · Enter = Start · Shift = Select
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
