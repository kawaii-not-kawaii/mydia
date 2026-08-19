defmodule Mydia.Downloads.QueueRedirectLocationTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Queue

  @base "https://indexer.example.com/getnzb/8629de1c9d5979442d1e25fd70eca66b.nzb"

  describe "resolve_location/2" do
    test "resolves the relative login redirect that crashed MovieSearch" do
      # Verbatim shape of the Location an indexer sends once its API key expires.
      location = "/login?redirect=%2Fgetnzb%2F8629de1c.nzb%2526i%253D59940"

      resolved = Queue.resolve_location(@base, location)

      assert %URI{scheme: "https", host: "indexer.example.com", path: "/login"} =
               URI.parse(resolved)
    end

    test "every relative location keeps a scheme" do
      for location <- ["/login", "login", "../other.nzb", "?retry=1", "//other.host/x"] do
        assert URI.parse(Queue.resolve_location(@base, location)).scheme != nil,
               "#{inspect(location)} produced a schemeless URL, which raises in Finch"
      end
    end

    test "absolute locations are left on their own host" do
      resolved = Queue.resolve_location(@base, "https://other.example.org/real.nzb")

      assert %URI{scheme: "https", host: "other.example.org", path: "/real.nzb"} =
               URI.parse(resolved)
    end

    test "a non-absolute base falls back instead of raising" do
      assert Queue.resolve_location("/not-absolute", "/login") == "/login"
    end
  end
end
