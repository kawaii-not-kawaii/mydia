defmodule Mydia.Plugins.HostFunctionsTest do
  use Mydia.DataCase, async: true

  import Mydia.MediaFixtures
  import Mydia.AccountsFixtures

  alias Mydia.Events
  alias Mydia.Plugins.Connections
  alias Mydia.Plugins.Error
  alias Mydia.Plugins.HostFunctions
  alias Mydia.Plugins.Plugin

  defp plugin(granted) do
    %Plugin{slug: "tester", name: "Tester", granted_capabilities: granted, enabled: true}
  end

  defp loopback_resolver, do: fn _ -> {:ok, [{127, 0, 0, 1}]} end

  describe "http_request/3 (net:http grant)" do
    setup do
      {:ok, bypass: Bypass.open()}
    end

    test "R6: a granted host succeeds", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/hook", fn conn ->
        Plug.Conn.resp(conn, 200, ~s({"ok":true}))
      end)

      p = plugin(%{"net:http" => ["allowed.test"]})

      assert {:ok, %{"status" => 200, "ok" => true, "body" => body}} =
               HostFunctions.http_request(
                 p,
                 %{"url" => "http://allowed.test:#{bypass.port}/hook", "method" => "POST"},
                 resolver: loopback_resolver(),
                 allow_private: true
               )

      assert body =~ "ok"
    end

    test "AE2: a host not on the grant is denied" do
      p = plugin(%{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.http_request(p, %{"url" => "https://evil.test/"},
                 resolver: loopback_resolver()
               )
    end

    test "a plugin without the net:http grant is denied before any request" do
      p = plugin(%{"events:subscribe" => ["media_item.added"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.http_request(p, %{"url" => "https://discord.com/"})
    end

    test "a missing url is rejected" do
      p = plugin(%{"net:http" => ["discord.com"]})
      assert {:error, %Error{type: :invalid_request}} = HostFunctions.http_request(p, %{})
    end
  end

  describe "stale-grant denials (a manifest revised after approval)" do
    defp declared_plugin(declared, granted) do
      %Plugin{
        slug: "tester",
        name: "Tester",
        capabilities: declared,
        granted_capabilities: granted,
        enabled: true
      }
    end

    test "a class the manifest declares but the grant lacks points at re-approval" do
      p = declared_plugin(%{"state:kv" => []}, %{"events:subscribe" => ["media_item.added"]})

      assert {:error, %Error{type: :capability_denied, message: msg}} =
               HostFunctions.kv_get(p, "k")

      assert msg =~ "re-approve"
    end

    test "a host the manifest declares but the grant lacks points at re-approval" do
      p = declared_plugin(%{"net:http" => ["api.example.com"]}, %{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied, message: msg}} =
               HostFunctions.http_request(p, %{"url" => "https://api.example.com/x"},
                 resolver: loopback_resolver()
               )

      assert msg =~ "re-approve"
    end

    test "a host the manifest never declared still reads as an allowlist denial" do
      p = declared_plugin(%{"net:http" => ["discord.com"]}, %{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied, message: msg}} =
               HostFunctions.http_request(p, %{"url" => "https://evil.test/"},
                 resolver: loopback_resolver()
               )

      assert msg =~ "allowlist"
      refute msg =~ "re-approve"
    end

    test "a namespace the manifest declares but the grant lacks points at re-approval" do
      item = media_item_fixture()
      p = declared_plugin(%{"data:read" => ["media_item"]}, %{"data:read" => []})

      assert {:error, %Error{type: :capability_denied, message: msg}} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})

      assert msg =~ "re-approve"
    end
  end

  describe "data_read/2 (data:read grant)" do
    test "returns a curated projection for a granted namespace" do
      item = media_item_fixture(%{title: "Dune", year: 2021, type: "movie"})
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:ok, projection} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})

      assert projection["title"] == "Dune"
      assert projection["year"] == 2021
      assert projection["type"] == "movie"
      # The projection is curated — it never carries the raw struct's internals.
      refute Map.has_key?(projection, :__struct__)
      refute Map.has_key?(projection, "metadata")
    end

    test "is denied without the data:read grant" do
      item = media_item_fixture()
      p = plugin(%{"net:http" => ["discord.com"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})
    end

    test "is denied when the namespace is not granted" do
      item = media_item_fixture()
      p = plugin(%{"data:read" => ["something_else"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.data_read(p, %{"resource" => "media_item", "id" => item.id})
    end

    test "an unknown resource is rejected" do
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:error, %Error{type: :invalid_request}} =
               HostFunctions.data_read(p, %{"resource" => "user", "id" => "1"})
    end

    test "a missing media item returns not_found" do
      p = plugin(%{"data:read" => ["media_item"]})

      assert {:error, %Error{type: type}} =
               HostFunctions.data_read(p, %{
                 "resource" => "media_item",
                 "id" => "00000000-0000-0000-0000-000000000000"
               })

      assert type in [:not_found, :invalid_request]
    end
  end

  describe "imports_for/2" do
    test "builds a per-invocation builder for the typed host interface" do
      builder = HostFunctions.imports_for("tester")
      assert is_function(builder, 1)

      imports = builder.(%{slug: "tester", invocation_id: "x", test_run: false})

      assert %{"mydia:plugin/host@1.1.0" => fns} = imports

      assert %{"http-request" => {:fn, f1}, "data-read" => {:fn, f2}, "log" => {:fn, f3}} = fns
      assert is_function(f1, 1) and is_function(f2, 1) and is_function(f3, 2)

      # 1.1 additions are all wired so a 1.1 guest instantiates.
      assert %{
               "kv-get" => {:fn, _},
               "kv-set" => {:fn, _},
               "kv-delete" => {:fn, _},
               "data-list" => {:fn, _},
               "connections-list" => {:fn, _},
               "connection-request" => {:fn, _}
             } = fns
    end
  end

  describe "kv host functions (state:kv grant)" do
    setup do
      {:ok, _} =
        Mydia.Settings.create_plugin_config(%{
          slug: "tester",
          name: "Tester",
          version: "1.0.0",
          source_url: "test",
          manifest: %{
            "slug" => "tester",
            "name" => "Tester",
            "version" => "1.0.0",
            "capabilities" => %{
              "events:subscribe" => ["media_item.added"],
              "state:kv" => []
            }
          },
          granted_capabilities: %{"state:kv" => []},
          enabled: false
        })

      :ok
    end

    test "set then get round-trips, returning an option" do
      p = plugin(%{"state:kv" => []})
      assert {:ok, true} = HostFunctions.kv_set(p, "k", "v")
      assert {:ok, {:some, "v"}} = HostFunctions.kv_get(p, "k")
    end

    test "kv-get on a missing key returns none" do
      p = plugin(%{"state:kv" => []})
      assert {:ok, :none} = HostFunctions.kv_get(p, "absent")
    end

    test "kv-delete removes the key" do
      p = plugin(%{"state:kv" => []})
      {:ok, true} = HostFunctions.kv_set(p, "k", "v")
      assert {:ok, true} = HostFunctions.kv_delete(p, "k")
      assert {:ok, :none} = HostFunctions.kv_get(p, "k")
    end

    test "AE4: a plugin without state:kv is denied across all three" do
      p = plugin(%{"events:subscribe" => ["media_item.added"]})
      assert {:error, %Error{type: :capability_denied}} = HostFunctions.kv_get(p, "k")
      assert {:error, %Error{type: :capability_denied}} = HostFunctions.kv_set(p, "k", "v")
      assert {:error, %Error{type: :capability_denied}} = HostFunctions.kv_delete(p, "k")
    end

    test "an empty key is rejected as invalid-request" do
      p = plugin(%{"state:kv" => []})
      assert {:error, %Error{type: :invalid_request}} = HostFunctions.kv_get(p, "")
    end
  end

  describe "connections_list/1 (users:connections grant)" do
    setup do
      {:ok, _} =
        Mydia.Settings.create_plugin_config(%{
          slug: "tester",
          name: "Tester",
          version: "1.0.0",
          source_url: "test",
          manifest: %{
            "slug" => "tester",
            "name" => "Tester",
            "version" => "1.0.0",
            "capabilities" => %{
              "events:subscribe" => ["media_item.added"],
              "users:connections" => []
            }
          },
          granted_capabilities: %{"users:connections" => []},
          enabled: false
        })

      %{user: user_fixture()}
    end

    test "returns identity and status, never a token", %{user: user} do
      {:ok, _} =
        Connections.connect("tester", user.id, %{
          access_token: "do-not-leak",
          external_user_id: "ext-9",
          external_username: "bob"
        })

      p = plugin(%{"users:connections" => []})
      assert {:ok, [record]} = HostFunctions.connections_list(p)

      assert record[:"user-id"] == user.id
      assert record.status == :connected
      assert record[:"external-username"] == {:some, "bob"}

      # No field in the record carries token material.
      refute inspect(record) =~ "do-not-leak"
      refute Map.has_key?(record, :access_token)
      refute Map.has_key?(record, :"access-token")
    end

    test "AE4: a plugin without users:connections is denied" do
      p = plugin(%{"events:subscribe" => ["media_item.added"]})
      assert {:error, %Error{type: :capability_denied}} = HostFunctions.connections_list(p)
    end
  end

  describe "data_list/2 (data:read grant)" do
    setup do
      {:ok, _} =
        Mydia.Settings.create_plugin_config(%{
          slug: "tester",
          name: "Tester",
          version: "1.0.0",
          source_url: "test",
          manifest: %{
            "slug" => "tester",
            "name" => "Tester",
            "version" => "1.0.0",
            "capabilities" => %{"events:subscribe" => ["media_item.added"]}
          },
          granted_capabilities: %{},
          enabled: false
        })

      :ok
    end

    defp list_req(namespace, opts \\ []) do
      %{
        namespace: namespace,
        cursor: Keyword.get(opts, :cursor, :none),
        "updated-since": Keyword.get(opts, :updated_since, :none),
        limit: Keyword.get(opts, :limit, :none)
      }
    end

    defp create_movie do
      {:ok, item} =
        Mydia.Media.create_media_item(%{
          title: "Movie #{System.unique_integer([:positive])}",
          type: "movie",
          year: 2024,
          tmdb_id: System.unique_integer([:positive]),
          imdb_id: "tt#{System.unique_integer([:positive])}"
        })

      item
    end

    # Walk every page, collecting the variant rows.
    defp walk(plugin, namespace, limit) do
      walk(plugin, namespace, limit, :none, [])
    end

    defp walk(plugin, namespace, limit, cursor, acc) do
      req = list_req(namespace, cursor: cursor, limit: {:some, limit})
      assert {:ok, %{items: items, "next-cursor": next}} = HostFunctions.data_list(plugin, req)
      acc = acc ++ items

      case next do
        :none -> acc
        {:some, _} = c -> walk(plugin, namespace, limit, c, acc)
      end
    end

    test "media_item pagination walks the full set exactly once" do
      ids = for _ <- 1..5, do: create_movie().id
      p = plugin(%{"data:read" => ["media_item"]})

      rows = walk(p, "media_item", 2)
      seen = Enum.map(rows, fn {:"media-item", rec} -> rec.id end)

      assert Enum.sort(seen) == Enum.sort(ids)
      assert length(seen) == length(Enum.uniq(seen))
    end

    test "an unknown but granted namespace is invalid-request" do
      # Granting an unknown namespace passes the grant gate, so the host reaches
      # the namespace dispatch and reports it has no backing.
      p = plugin(%{"data:read" => ["bogus"]})

      assert {:error, %Error{type: :invalid_request}} =
               HostFunctions.data_list(p, list_req("bogus"))
    end

    test "a real namespace that is not granted is denied" do
      p = plugin(%{"events:subscribe" => ["media_item.added"]})

      assert {:error, %Error{type: :capability_denied}} =
               HostFunctions.data_list(p, list_req("media_item"))
    end
  end

  describe "connection_request/4 (host-attached auth)" do
    setup do
      {:ok, _} =
        Mydia.Settings.create_plugin_config(%{
          slug: "tester",
          name: "Tester",
          version: "1.0.0",
          source_url: "test",
          manifest: %{
            "slug" => "tester",
            "name" => "Tester",
            "version" => "1.0.0",
            "capabilities" => %{"events:subscribe" => ["media_item.added"]}
          },
          granted_capabilities: %{},
          enabled: false
        })

      user = user_fixture()

      {:ok, conn} =
        Connections.connect("tester", user.id, %{access_token: "secret-bearer"})

      %{bypass: Bypass.open(), connection: conn}
    end

    test "injects the host-held bearer token and strips any guest Authorization",
         %{bypass: bypass, connection: conn} do
      parent = self()

      Bypass.expect_once(bypass, "GET", "/sync/activities", fn c ->
        send(parent, {:auth, Plug.Conn.get_req_header(c, "authorization")})
        Plug.Conn.resp(c, 200, ~s({"ok":true}))
      end)

      p = plugin(%{"net:http" => ["127.0.0.1"], "users:connections" => []})

      request = %{
        "url" => "http://127.0.0.1:#{bypass.port}/sync/activities",
        "method" => "GET",
        "headers" => %{"authorization" => "Bearer guest-forged"}
      }

      assert {:ok, %{"status" => 200}} =
               HostFunctions.connection_request(p, conn.id, request,
                 resolver: loopback_resolver(),
                 allow_private: true
               )

      assert_received {:auth, ["Bearer secret-bearer"]}
    end

    test "a connection that does not belong to the plugin is not found", %{connection: _conn} do
      p = plugin(%{"net:http" => ["127.0.0.1"], "users:connections" => []})

      assert {:error, %Error{type: :not_found}} =
               HostFunctions.connection_request(
                 p,
                 Ecto.UUID.generate(),
                 %{"url" => "http://127.0.0.1/x"},
                 resolver: loopback_resolver(),
                 allow_private: true
               )
    end
  end
end
