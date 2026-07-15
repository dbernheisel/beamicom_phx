defmodule BeamicomPhx.AV.RtpBroadcast do
  @moduledoc """
  Server-side broadcast: encode the emulator's A/V once and send it as RTP over
  UDP to the client node. Runs persistently in server mode when a target is set,
  independent of the per-browser WebRTC pipelines.

  A short GOP (periodic IDRs) lets a client's late-joining browsers recover — the
  relay has no encoder and can't satisfy their keyframe requests otherwise.
  """
  use Membrane.Pipeline

  alias Membrane.{RTP, UDP}

  @video_ssrc 111_111
  @audio_ssrc 222_222
  @gop 60

  @impl true
  def handle_init(_ctx, opts) do
    {ip, port} = Keyword.fetch!(opts, :target)

    spec = [
      child(:rtp, %RTP.SessionBin{fmt_mapping: %{96 => {:H264, 90_000}, 111 => {:OPUS, 48_000}}}),
      child(:video_src, BeamicomPhx.AV.VideoSource)
      |> child(:scaler, %Membrane.FFmpeg.SWScale.Converter{format: :I420})
      |> child(:h264, %Membrane.H264.FFmpeg.Encoder{
        tune: :zerolatency,
        preset: :ultrafast,
        profile: :baseline,
        gop_size: @gop
      })
      |> child(:h264_parser, %Membrane.H264.Parser{output_alignment: :nalu})
      |> via_in(Pad.ref(:input, @video_ssrc), options: [payloader: Membrane.RTP.H264.Payloader])
      |> get_child(:rtp),
      get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, @video_ssrc),
        options: [encoding: :H264, payload_type: 96, clock_rate: 90_000]
      )
      |> child(:udp_video, %UDP.Sink{destination_address: ip, destination_port_no: port}),
      child(:audio_src, BeamicomPhx.AV.AudioSource)
      |> child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: %Membrane.RawAudio{
          channels: 1,
          sample_rate: 48_000,
          sample_format: :s16le
        }
      })
      |> child(:opus, Membrane.Opus.Encoder)
      |> via_in(Pad.ref(:input, @audio_ssrc), options: [payloader: Membrane.RTP.Opus.Payloader])
      |> get_child(:rtp),
      get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, @audio_ssrc),
        options: [encoding: :OPUS, payload_type: 111, clock_rate: 48_000]
      )
      |> child(:udp_audio, %UDP.Sink{destination_address: ip, destination_port_no: port + 2})
    ]

    {[spec: spec], %{}}
  end
end
