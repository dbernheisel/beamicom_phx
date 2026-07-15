defmodule BeamicomPhx.AV.Relay do
  @moduledoc """
  Client-side relay: receive the server's RTP over UDP, depayload to encoded
  H264/Opus (no re-encode), and fan out to one `Membrane.WebRTC.Sink` per browser.

  Browsers attach with `add_browser/3` from their LiveView; the Relay monitors the
  LiveView pid and removes that browser's sink on `:DOWN` (reliable teardown that
  does not depend on LiveView `terminate/2`).

  A browser can attach before the server's stream has arrived (the depayloader Tees
  don't exist yet). Such attaches are QUEUED and drained once both streams are up,
  so an early viewer can never reference missing children and crash the shared relay.

  ## Pad choice: `:push_output` on `Membrane.Tee`

  `Membrane.Tee` has `:output` (pull/auto — slowest consumer back-pressures everyone)
  and `:push_output` (push — forwarded regardless of demand). RTP over UDP is a push
  source with no back-pressure, so the fan-out uses `:push_output`; otherwise one slow
  browser sink would stall the whole relay.
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

    {[spec: spec], %{tees: MapSet.new(), browsers: %{}, pending: []}}
  end

  # SessionBin re-notifies {:new_rtp_stream, ssrc, payload_type, extensions} from its
  # internal ssrc_router. Video is PT 96, audio PT 111 (set by the server's SessionBin).
  # Source: deps/membrane_rtp_plugin/lib/membrane/rtp/session_bin.ex
  @impl true
  def handle_child_notification({:new_rtp_stream, ssrc, 96, _ext}, :rtp, _ctx, state) do
    # The H264 depayloader emits NAL units carrying RTP metadata, but WebRTC.Sink's
    # re-payloader needs the `:h264` NAL metadata that Membrane.H264.Parser attaches
    # (its output is nalu_in_metadata?: true). Same parser the server runs after its
    # encoder — without it the sink's payloader KeyErrors on `:h264` per buffer.
    tee_spec =
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.H264.Depayloader, encoding: :H264]
      )
      |> child(:relay_h264_parser, %Membrane.H264.Parser{output_alignment: :nalu})
      |> child(:video_tee, Membrane.Tee)

    stream_ready(state, :video, tee_spec)
  end

  def handle_child_notification({:new_rtp_stream, ssrc, 111, _ext}, :rtp, _ctx, state) do
    # The Opus depayloader emits %RemoteStream{content_format: Opus}, but WebRTC.Sink
    # accepts raw `Membrane.Opus`. Membrane.Opus.Parser bridges the two (RemoteStream
    # in -> %Opus{} out). (Video needs no parser: the H264 depayloader already emits
    # %H264{alignment: :nalu}, which the sink accepts.)
    tee_spec =
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.Opus.Depayloader, encoding: :OPUS]
      )
      |> child(:opus_parser, Membrane.Opus.Parser)
      |> child(:audio_tee, Membrane.Tee)

    stream_ready(state, :audio, tee_spec)
  end

  def handle_child_notification(_msg, _child, _ctx, state), do: {[], state}

  # handle_call must return {[reply: value | other_actions], state}; the reply action
  # unblocks the caller. Source: deps/membrane_core/lib/membrane/pipeline/action.ex
  @impl true
  def handle_call({:add_browser, id, lv_pid, signaling}, _ctx, state) do
    Process.monitor(lv_pid)

    if ready?(state) do
      {[reply: :ok, spec: browser_spec(id, signaling)], put_in(state, [:browsers, lv_pid], id)}
    else
      # Stream not up yet — queue; attach when both Tees arrive (see stream_ready/3).
      {[reply: :ok], %{state | pending: [{id, lv_pid, signaling} | state.pending]}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, lv_pid, _reason}, _ctx, state) do
    state = %{state | pending: Enum.reject(state.pending, fn {_id, lv, _sig} -> lv == lv_pid end)}

    case Map.pop(state.browsers, lv_pid) do
      {nil, _} -> {[], state}
      {id, browsers} -> {[remove_children: [{:sink, id}]], %{state | browsers: browsers}}
    end
  end

  # Record the new Tee; once both video+audio are present, drain any queued browsers.
  defp stream_ready(state, kind, tee_spec) do
    state = %{state | tees: MapSet.put(state.tees, kind)}

    if ready?(state) and state.pending != [] do
      specs = Enum.flat_map(state.pending, fn {id, _lv, sig} -> browser_spec(id, sig) end)

      browsers =
        Enum.reduce(state.pending, state.browsers, fn {id, lv, _}, acc -> Map.put(acc, lv, id) end)

      {[spec: [tee_spec | specs]], %{state | pending: [], browsers: browsers}}
    else
      {[spec: tee_spec], state}
    end
  end

  defp ready?(state),
    do: MapSet.member?(state.tees, :video) and MapSet.member?(state.tees, :audio)

  # Children + links to attach one browser's WebRTC.Sink to both Tees.
  defp browser_spec(id, signaling) do
    sink = {:sink, id}

    [
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
  end
end
