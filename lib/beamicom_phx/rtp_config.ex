defmodule BeamicomPhx.RtpConfig do
  @moduledoc """
  Reads the relay's UDP endpoints from the environment.

  - `BEAMICOM_RTP_TARGET` ("host:port") — where the SERVER sends its RTP broadcast
    (the client node). Video goes to `port`, audio to `port + 2`.
  - `BEAMICOM_RTP_LISTEN` (integer, default 5000) — the CLIENT's base receive port
    (video on base, audio on base + 2).
  """

  @doc "The server's broadcast target as `{ip_tuple, port}`, or nil when unset."
  def target, do: parse_target(System.get_env("BEAMICOM_RTP_TARGET"))

  @doc "The client's base UDP receive port."
  def listen_port, do: String.to_integer(System.get_env("BEAMICOM_RTP_LISTEN", "5000"))

  @doc false
  def parse_target(nil), do: nil
  def parse_target(""), do: nil

  def parse_target(target) when is_binary(target) do
    with [host, port] <- String.split(target, ":"),
         {:ok, ip} <- :inet.parse_address(String.to_charlist(host)),
         {port, ""} <- Integer.parse(port) do
      {ip, port}
    else
      _ ->
        raise ArgumentError, "invalid BEAMICOM_RTP_TARGET #{inspect(target)}, expected host:port"
    end
  end
end
