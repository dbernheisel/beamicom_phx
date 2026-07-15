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
    mode = Application.get_env(:beamicom_phx, :mode, :server)

    socket =
      if connected?(socket) do
        signaling = Membrane.WebRTC.Signaling.new()

        case mode do
          # Client node: attach to the shared Relay, which links a WebRTC.Sink for
          # this browser and monitors us — it tears the sink down when we disconnect.
          :client ->
            BeamicomPhx.AV.Relay.add_browser(socket.id, self(), signaling)

          # Server node: start this browser's own encode pipeline, linked to this
          # LiveView so it dies with the socket.
          _server ->
            {:ok, _supervisor, _pipeline} =
              Membrane.Pipeline.start_link(BeamicomPhx.AV.Pipeline, egress_signaling: signaling)
        end

        Player.attach(socket, id: "videoPlayer", signaling: signaling)
      else
        socket
      end

    # `held` = controller buttons currently down (the NES controller is stateful, so
    # we resend the whole set on every change). Server mode also accepts a dropped
    # ROM to (re)load the emulator.
    socket = assign(socket, held: MapSet.new(), mode: mode, rom_name: nil)

    socket =
      if mode == :server do
        # accept: :any because ".nes" isn't a registered MIME type/extension that
        # LiveView's accept filter recognizes; we validate the extension in the handler.
        allow_upload(socket, :rom,
          accept: :any,
          max_entries: 1,
          auto_upload: true,
          progress: &handle_rom_progress/3
        )
      else
        socket
      end

    {:ok, socket}
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
      <label :if={@mode == :server} class="crt__rom" phx-drop-target={@uploads.rom.ref}>
        <.live_file_input upload={@uploads.rom} class="crt__rom-input" />
        {if @rom_name,
          do: "▸ #{@rom_name} — drop a .nes to change",
          else: "Drop a .nes ROM here to load"}
      </label>
    </div>
    """
  end

  # A dropped/selected .nes finished uploading: copy it out of the temp dir and
  # (re)load the emulator. All viewers pick up the new game via the shared Output.
  defp handle_rom_progress(:rom, entry, socket) do
    name = entry.client_name || ""

    cond do
      not entry.done? ->
        {:noreply, socket}

      not String.ends_with?(String.downcase(name), ".nes") ->
        socket =
          socket
          |> cancel_upload(:rom, entry.ref)
          |> put_flash(:error, "#{name} is not a .nes ROM")

        {:noreply, socket}

      true ->
        path =
          consume_uploaded_entry(socket, entry, fn %{path: tmp} ->
            dest = Path.join(System.tmp_dir!(), "beamicom_current_rom.nes")
            File.cp!(tmp, dest)
            {:ok, dest}
          end)

        socket =
          case BeamicomPhx.Emulator.load(path) do
            :ok -> assign(socket, rom_name: name)
            {:error, _reason} -> put_flash(socket, :error, "Couldn't load #{name}")
          end

        {:noreply, socket}
    end
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
