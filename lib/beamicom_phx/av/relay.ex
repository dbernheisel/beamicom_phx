defmodule BeamicomPhx.AV.Relay do
  @moduledoc """
  Client-side relay: receive the server's RTP over UDP, depayload to encoded
  H264/Opus (no re-encode), and fan out to one `Membrane.WebRTC.Sink` per browser.

  Browsers attach with `add_browser/3` from their LiveView; the Relay monitors the
  LiveView pid and removes that browser's sink on `:DOWN` (reliable teardown that
  does not depend on LiveView `terminate/2`).

  ## Pad choice: `:push_output` on `Membrane.Tee`

  `Membrane.Tee` has two output pad types:
  - `:output` — pull/auto flow control; the slowest consumer dictates throughput.
  - `:push_output` — push flow control; data is forwarded regardless of demand.

  RTP over UDP is a push source (no back-pressure from the network). Using `:output`
  would stall the tee if any browser's sink is slow. `:push_output` matches the live
  streaming pattern: data arrives at the network rate and is forwarded to all sinks.
  Source: `deps/membrane_core/lib/membrane/tee.ex`.
  """
  use Membrane.Pipeline

  alias Membrane.{RTP, UDP}

  @name __MODULE__

  def start_link(opts), do: Membrane.Pipeline.start_link(__MODULE__, opts, name: @name)

  @doc "Attach a browser: link a WebRTC.Sink (using `signaling`) to the relayed A/V."
  @spec add_browser(term(), pid(), term()) :: :ok
  def add_browser(browser_id, lv_pid, signaling),
    do: Membrane.Pipeline.call(@name, {:add_browser, browser_id, lv_pid, signaling})

  @impl true
  def handle_init(_ctx, opts) do
    port = Keyword.fetch!(opts, :listen_port)

    spec = [
      child(:rtp, %RTP.SessionBin{fmt_mapping: %{96 => {:H264, 90_000}, 111 => {:OPUS, 48_000}}}),
      child(:udp_video, %UDP.Source{local_port_no: port})
      |> via_in(Pad.ref(:rtp_input, :video))
      |> get_child(:rtp),
      child(:udp_audio, %UDP.Source{local_port_no: port + 2})
      |> via_in(Pad.ref(:rtp_input, :audio))
      |> get_child(:rtp)
    ]

    {[spec: spec], %{tees: %{}, browsers: %{}}}
  end

  # SessionBin re-notifies the {:new_rtp_stream, ssrc, pt, extensions} notification
  # from its internal ssrc_router to the parent pipeline.
  # Source: deps/membrane_rtp_plugin/lib/membrane/rtp/session_bin.ex handle_child_notification/4
  @impl true
  def handle_child_notification({:new_rtp_stream, ssrc, 96, _ext}, :rtp, _ctx, state) do
    spec =
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.H264.Depayloader, encoding: :H264]
      )
      |> child(:video_tee, Membrane.Tee)

    {[spec: spec], put_in(state, [:tees, :video], true)}
  end

  def handle_child_notification({:new_rtp_stream, ssrc, 111, _ext}, :rtp, _ctx, state) do
    spec =
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.Opus.Depayloader, encoding: :OPUS]
      )
      |> child(:audio_tee, Membrane.Tee)

    {[spec: spec], put_in(state, [:tees, :audio], true)}
  end

  def handle_child_notification(_msg, _child, _ctx, state), do: {[], state}

  # handle_call must return {[reply: reply_val | other_actions], state}.
  # The {:reply, value} action sends the reply to the blocked caller.
  # Source: deps/membrane_core/lib/membrane/pipeline/action.ex type reply/0
  # Source: deps/membrane_core/lib/membrane/pipeline.ex handle_call/3 callback spec
  @impl true
  def handle_call({:add_browser, id, lv_pid, signaling}, _ctx, state) do
    Process.monitor(lv_pid)
    sink = {:sink, id}

    # `:push_output` is used (not `:output`) because RTP/UDP is a push source.
    # See moduledoc for rationale.
    spec = [
      child(sink, %Membrane.WebRTC.Sink{
        signaling: signaling,
        tracks: [:audio, :video],
        video_codec: :h264
      }),
      get_child(:video_tee)
      |> via_out(Pad.ref(:push_output, id))
      |> via_in(Pad.ref(:input, {id, :video}), options: [kind: :video])
      |> get_child(sink),
      get_child(:audio_tee)
      |> via_out(Pad.ref(:push_output, id))
      |> via_in(Pad.ref(:input, {id, :audio}), options: [kind: :audio])
      |> get_child(sink)
    ]

    {[reply: :ok, spec: spec], put_in(state, [:browsers, lv_pid], id)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, lv_pid, _reason}, _ctx, state) do
    case Map.pop(state.browsers, lv_pid) do
      {nil, _} -> {[], state}
      {id, browsers} -> {[remove_children: [{:sink, id}]], %{state | browsers: browsers}}
    end
  end
end
