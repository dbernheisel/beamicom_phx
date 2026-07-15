defmodule BeamicomPhx.RtpConfigTest do
  use ExUnit.Case, async: true
  alias BeamicomPhx.RtpConfig

  describe "parse_target/1" do
    test "parses host:port into an {ip_tuple, port}" do
      assert RtpConfig.parse_target("127.0.0.1:5000") == {{127, 0, 0, 1}, 5000}
    end

    test "returns nil for nil or blank" do
      assert RtpConfig.parse_target(nil) == nil
      assert RtpConfig.parse_target("") == nil
    end

    test "raises on a malformed target" do
      assert_raise ArgumentError, fn -> RtpConfig.parse_target("nope") end
    end
  end
end
