defmodule Druid.LookupsTest do
  use ExUnit.Case, async: true
  alias Druid.Lookups
  alias Druid.Lookups.Lookup
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  @map_lookup """
  {"type": "map", "map": <%= json @values %>}
  """

  defp write!(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp opts(dir, extra \\ []) do
    Keyword.merge([path: dir, assigns: %{values: %{"US" => "United States"}}], extra)
  end

  defp factory(values), do: %{"type" => "map", "map" => values}

  describe "render/2" do
    test "puts top-level templates in the default tier, others in their directory's", %{
      tmp_dir: dir
    } do
      write!(dir, "countries.json.eex", @map_lookup)
      write!(dir, "realtime/regions.json.eex", @map_lookup)

      assert [
               %Lookup{name: "countries", tier: "__default", lookup: "countries", factory: f},
               %Lookup{name: "realtime/regions", tier: "realtime", lookup: "regions"}
             ] = Lookups.render(TestRepo, opts(dir))

      assert f == factory(%{"US" => "United States"})
    end

    test "the :tier option changes the default tier", %{tmp_dir: dir} do
      write!(dir, "countries.json.eex", @map_lookup)
      assert [%Lookup{tier: "other"}] = Lookups.render(TestRepo, opts(dir, tier: "other"))
    end

    test "raises on templates nested deeper than a tier directory", %{tmp_dir: dir} do
      write!(dir, "a/b/countries.json.eex", @map_lookup)

      assert_raise Lookups.Error, ~r/a\/b\/countries: lookup templates go directly/, fn ->
        Lookups.render(TestRepo, opts(dir))
      end
    end

    test "raises when a template renders the version wrapper", %{tmp_dir: dir} do
      write!(dir, "countries.json", ~s({"version": "v1", "lookupExtractorFactory": {}}))

      assert_raise Lookups.Error, ~r/should render only the lookupExtractorFactory/, fn ->
        Lookups.render(TestRepo, opts(dir))
      end
    end

    test "raises when a template doesn't render a factory", %{tmp_dir: dir} do
      write!(dir, "countries.json", "[]")

      assert_raise Lookups.Error, ~r/must render a JSON object with a "type"/, fn ->
        Lookups.render(TestRepo, opts(dir))
      end
    end

    test "raises when two templates define the same lookup", %{tmp_dir: dir} do
      write!(dir, "countries.json.eex", @map_lookup)
      write!(dir, "__default/countries.json.eex", @map_lookup)

      assert_raise Lookups.Error, ~r/same lookup: __default\/countries/, fn ->
        Lookups.render(TestRepo, opts(dir))
      end
    end
  end

  describe "next_version/2" do
    @now ~U[2026-11-15 09:30:00Z]

    test "uses a timestamp version" do
      assert Lookups.next_version(nil, @now) == "v20261115T093000Z"
      assert Lookups.next_version("v1", @now) == "v20261115T093000Z"
      assert Lookups.next_version("v20261114T000000Z", @now) == "v20261115T093000Z"
    end

    test "extends a current version that already sorts later" do
      version = Lookups.next_version("v9", @now)
      assert version == "v9-v20261115T093000Z"
      assert version > "v9"

      assert Lookups.next_version("v20261115T093000Z", @now) ==
               "v20261115T093000Z-v20261115T093000Z"
    end
  end

  describe "sync/2" do
    # A fake Coordinator. `current` is what Druid returns for all lookups, or
    # :uninitialized for a cluster with no lookups yet.
    defp druid(current, opts \\ []) do
      fail = Keyword.get(opts, :fail, [])
      test_pid = self()

      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case {conn.method, conn.path_info} do
          {"GET", [_, _, _, "lookups", "config", "all"]} when current == :uninitialized ->
            conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "Not Found"})

          {"GET", [_, _, _, "lookups", "config", "all"]} ->
            Req.Test.json(conn, current)

          {"POST", [_, _, _, "lookups", "config"]} ->
            send(test_pid, {:initialize, Jason.decode!(body)})
            conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})

          {"POST", [_, _, _, "lookups", "config", tier, name]} ->
            send(test_pid, {:set, tier, name, Jason.decode!(body)})

            if name in fail do
              conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "nope"})
            else
              conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
            end

          {"DELETE", [_, _, _, "lookups", "config", tier, name]} ->
            send(test_pid, {:delete, tier, name})
            conn |> Plug.Conn.put_status(202) |> Req.Test.json(%{})
        end
      end
    end

    defp stored(version, values),
      do: %{"version" => version, "lookupExtractorFactory" => factory(values)}

    test "creates, updates with a later version, and leaves lookups unchanged", %{tmp_dir: dir} do
      for name <- ["a", "b", "c"], do: write!(dir, "#{name}.json.eex", @map_lookup)

      current = %{
        "__default" => %{
          "b" => stored("v9", %{"US" => "USA"}),
          "c" => stored("v1", %{"US" => "United States"})
        }
      }

      assert [
               created: %Lookup{lookup: "a"},
               updated: %Lookup{lookup: "b"},
               unchanged: %Lookup{lookup: "c"}
             ] = Lookups.sync(TestRepo, opts(dir, plug: druid(current)))

      assert_received {:set, "__default", "a", %{"version" => "v2" <> _} = a}
      assert a["lookupExtractorFactory"] == factory(%{"US" => "United States"})
      assert_received {:set, "__default", "b", %{"version" => "v9-v2" <> _}}
      refute_received {:set, _, "c", _}
      refute_received {:initialize, _}
    end

    test "initializes lookups on a cluster that has none", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @map_lookup)

      assert [{:would_create, _}] =
               Lookups.sync(TestRepo, opts(dir, plug: druid(:uninitialized), dry_run: true))

      refute_received {:initialize, _}

      assert [{:created, _}] = Lookups.sync(TestRepo, opts(dir, plug: druid(:uninitialized)))
      assert_received {:initialize, %{}}
      assert_received {:set, "__default", "a", _}
    end

    test "dry_run submits nothing", %{tmp_dir: dir} do
      for name <- ["a", "b"], do: write!(dir, "#{name}.json.eex", @map_lookup)
      current = %{"__default" => %{"b" => stored("v1", %{})}}

      assert [would_create: _, would_update: _] =
               Lookups.sync(TestRepo, opts(dir, plug: druid(current), dry_run: true))

      refute_received {:set, _, _, _}
    end

    test "prune deletes lookups without a template, in any tier", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @map_lookup)

      current = %{
        "__default" => %{
          "a" => stored("v1", %{"US" => "United States"}),
          "old" => stored("v1", %{})
        },
        "realtime" => %{"gone" => stored("v1", %{})}
      }

      assert [{:unchanged, _}, {:would_delete, "__default/old"}, {:would_delete, "realtime/gone"}] =
               Lookups.sync(TestRepo, opts(dir, plug: druid(current), prune: true, dry_run: true))

      refute_received {:delete, _, _}

      assert [{:unchanged, _}, {:deleted, "__default/old"}, {:deleted, "realtime/gone"}] =
               Lookups.sync(TestRepo, opts(dir, plug: druid(current), prune: true))

      assert_received {:delete, "__default", "old"}
      assert_received {:delete, "realtime", "gone"}
    end

    test "prune can't be combined with only", %{tmp_dir: dir} do
      assert_raise ArgumentError, fn ->
        Lookups.sync(TestRepo, opts(dir, prune: true, only: ["a"]))
      end
    end

    test "keeps going after a failed request", %{tmp_dir: dir} do
      for name <- ["a", "b"], do: write!(dir, "#{name}.json.eex", @map_lookup)

      assert [{:error, %Lookup{lookup: "a"}, %Druid.Client.RequestError{}}, {:created, _}] =
               Lookups.sync(TestRepo, opts(dir, plug: druid(%{}, fail: ["a"])))
    end
  end
end
