defmodule BeamicomPhx.AV.Pipeline do
  @moduledoc """
  Encodes the emulator's A/V once and sends it to one browser over WebRTC.

  ponytail: one pipeline per browser connection (started by WatchLive). Fine for
  watch-only Phase 1. Upgrade path when multi-viewer/RTP (Phase 2) lands: a single
  shared encoder fanned out with `Membrane.Tee` to per-peer Sinks + the RTP output.
  """
  use Membrane.Pipeline

  @impl true
  def handle_init(_ctx, opts) do
    sink = %Membrane.WebRTC.Sink{
      signaling: Keyword.fetch!(opts, :egress_signaling),
      tracks: [:audio, :video],
      video_codec: :h264
    }

    spec = [
      child(:sink, sink),

      # Video: RGB frames -> I420 -> H264 (:au) -> parser (:nalu) -> WebRTC.
      # The FFmpeg encoder emits alignment: :au; the WebRTC.Sink requires alignment: :nalu,
      # so Membrane.H264.Parser (from membrane_h26x_plugin) re-aligns between them.
      # ponytail: encoder defaults (no zerolatency tuning) until latency is measured.
      child(:video_src, BeamicomPhx.AV.VideoSource)
      |> child(:scaler, %Membrane.FFmpeg.SWScale.Converter{format: :I420})
      |> child(:h264, Membrane.H264.FFmpeg.Encoder)
      |> child(:h264_parser, %Membrane.H264.Parser{output_alignment: :nalu})
      |> via_in(:input, options: [kind: :video])
      |> get_child(:sink),

      # Audio: 44100 s16le mono -> 48000 s16le mono (Opus requires 48k) -> Opus -> WebRTC.
      # SWResample auto-detects input format from upstream RawAudio; only output_stream_format needed.
      child(:audio_src, BeamicomPhx.AV.AudioSource)
      |> child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: %Membrane.RawAudio{
          channels: 1,
          sample_rate: 48_000,
          sample_format: :s16le
        }
      })
      |> child(:opus, Membrane.Opus.Encoder)
      |> via_in(:input, options: [kind: :audio])
      |> get_child(:sink)
    ]

    {[spec: spec], %{}}
  end
end
