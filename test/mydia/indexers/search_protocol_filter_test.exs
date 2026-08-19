defmodule Mydia.Indexers.SearchProtocolFilterTest do
  @moduledoc """
  The auto-search path must not select a release no configured download client
  can accept. Before this filter existed, a Usenet result grabbed with only a
  torrent client configured fetched the .nzb from the indexer and only then
  failed client selection, discarding the job.
  """
  use Mydia.DataCase, async: false

  alias Mydia.Downloads.Queue
  alias Mydia.Indexers

  defp client_fixture(attrs) do
    {:ok, config} =
      Mydia.Settings.create_download_client_config(
        Map.merge(
          %{
            name: "c-#{System.unique_integer([:positive])}",
            type: :qbittorrent,
            host: "localhost",
            port: 8080,
            enabled: true
          },
          attrs
        )
      )

    config
  end

  describe "configured_protocols/0" do
    test "is :any when nothing is enabled, so searches stay permissive" do
      assert Queue.configured_protocols() == :any
    end

    test "reports only what an enabled client accepts" do
      client_fixture(%{type: :qbittorrent})
      assert Queue.configured_protocols() == [:torrent]
    end

    test "a disabled client contributes nothing" do
      client_fixture(%{type: :sabnzbd, enabled: false})
      assert Queue.configured_protocols() == :any
    end

    test "unions across clients of different protocols" do
      client_fixture(%{type: :qbittorrent})
      client_fixture(%{type: :sabnzbd})
      assert Enum.sort(Queue.configured_protocols()) == [:nzb, :torrent]
    end
  end

  describe "search_all/2 protocol filtering" do
    setup do
      Mydia.Settings.list_indexer_configs()
      |> Enum.reject(&is_nil(&1.inserted_at))
      |> Enum.each(&Mydia.Settings.update_indexer_config(&1, %{enabled: false}))

      bypass = Bypass.open()

      Bypass.stub(bypass, "GET", "/api/v1/search", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!([torrent_item(), nzb_item()]))
      end)

      {:ok, _} =
        Mydia.Settings.create_indexer_config(%{
          name: "Protocol Test Indexer",
          type: :prowlarr,
          base_url: "http://localhost:#{bypass.port}",
          api_key: "k",
          enabled: true
        })

      :ok
    end

    defp torrent_item do
      %{
        "title" => "Some.Movie.2026.1080p.WEB-DL-GRP",
        "downloadUrl" => "http://indexer.test/download/1.torrent",
        "protocol" => "torrent",
        "seeders" => 50,
        "size" => 5_000_000_000,
        "indexer" => "TorrentSite"
      }
    end

    defp nzb_item do
      %{
        "title" => "Some.Movie.2026.2160p.WEB-DL-GRP",
        "downloadUrl" => "http://indexer.test/getnzb/abc.nzb",
        "protocol" => "usenet",
        "size" => 9_000_000_000,
        "indexer" => "UsenetSite"
      }
    end

    defp titles(results), do: Enum.map(results, & &1.title)

    test "drops the NZB when only a torrent client is configured" do
      client_fixture(%{type: :qbittorrent})

      {:ok, %{results: results}} = Indexers.search_all("some movie")

      assert titles(results) == ["Some.Movie.2026.1080p.WEB-DL-GRP"],
             "an NZB survived with no Usenet client, which is the grab that discards the job"
    end

    test "keeps the NZB once a Usenet client exists" do
      client_fixture(%{type: :qbittorrent})
      client_fixture(%{type: :sabnzbd})

      {:ok, %{results: results}} = Indexers.search_all("some movie")

      assert length(results) == 2
    end

    test "keeps everything when no client is configured at all" do
      # A fresh install must not look like every indexer returned nothing.
      {:ok, %{results: results}} = Indexers.search_all("some movie")

      assert length(results) == 2
    end

    test "manual search still sees the NZB it cannot download" do
      client_fixture(%{type: :qbittorrent})

      {:ok, %{results: results}} =
        Indexers.search_all("some movie", include_undownloadable: true)

      assert length(results) == 2
    end
  end
end
