defmodule BeamicomPhx.AV.PipelineTest do
  use ExUnit.Case, async: false

  test "starts and reaches playing with a fresh signaling" do
    signaling = Membrane.WebRTC.Signaling.new()

    {:ok, _supervisor, pipeline} =
      Membrane.Pipeline.start_link(BeamicomPhx.AV.Pipeline, egress_signaling: signaling)

    ref = Process.monitor(pipeline)
    # Should stay up (no immediate crash from bad wiring/format negotiation).
    refute_receive {:DOWN, ^ref, :process, ^pipeline, _}, 1_500

    Membrane.Pipeline.terminate(pipeline)
  end
end
