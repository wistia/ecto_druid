defmodule Druid.RetentionTest do
  use ExUnit.Case, async: true
  alias Druid.Retention
  alias Druid.Retention.Rules
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  @rules """
  [
    {"type": "loadByPeriod", "period": "P2Y", "tieredReplicants": {<%= json @tier %>: <%= @replicas %>}},
    {"type": "dropForever"}
  ]
  """

  defp write!(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp opts(dir, extra \\ []) do
    Keyword.merge([path: dir, assigns: %{tier: "hot", replicas: 2}], extra)
  end

  describe "render/2" do
    test "names the data source after the file", %{tmp_dir: dir} do
      write!(dir, "nested/page_views.json.eex", @rules)

      assert [%Rules{name: "nested/page_views", data_source: "page_views", rules: rules}] =
               Retention.render(TestRepo, opts(dir))

      assert [%{"tieredReplicants" => %{"hot" => 2}}, %{"type" => "dropForever"}] = rules
    end

    test "takes per-template assigns", %{tmp_dir: dir} do
      write!(dir, "page_views.json.eex", @rules)

      assert [%Rules{rules: [%{"tieredReplicants" => %{"hot" => 1}}, _]}] =
               Retention.render(TestRepo, opts(dir, specs: %{"page_views" => %{replicas: 1}}))
    end

    test "an object names the data source, for the cluster default", %{tmp_dir: dir} do
      write!(
        dir,
        "defaults.json",
        ~s({"dataSource": "_default", "rules": [{"type": "loadForever"}]})
      )

      assert [%Rules{name: "defaults", data_source: "_default"}] =
               Retention.render(TestRepo, opts(dir))
    end

    test "raises when a template doesn't render rules", %{tmp_dir: dir} do
      write!(dir, "a.json", ~s({"type": "loadForever"}))

      assert_raise Retention.Error, ~r/a must render a list of rules/, fn ->
        Retention.render(TestRepo, opts(dir))
      end

      write!(dir, "a.json", ~s([{"period": "P1D"}]))

      assert_raise Retention.Error, ~r/every rule must be an object with a "type"/, fn ->
        Retention.render(TestRepo, opts(dir))
      end
    end

    test "raises when two templates name the same data source", %{tmp_dir: dir} do
      write!(dir, "a/page_views.json", "[]")
      write!(dir, "b/page_views.json", "[]")

      assert_raise Retention.Error,
                   ~r/same data source: page_views \(a\/page_views, b\/page_views\)/,
                   fn -> Retention.render(TestRepo, opts(dir)) end
    end

    test "raises on unknown template names", %{tmp_dir: dir} do
      write!(dir, "a.json", "[]")

      assert_raise Retention.Error, ~r/no retention templates named: b/, fn ->
        Retention.render(TestRepo, opts(dir, only: ["b"]))
      end
    end
  end

  describe "normalize/1" do
    test "fills in Druid's defaults and normalizes intervals" do
      rules = [
        %{"type" => "loadByPeriod", "period" => "P2Y"},
        %{"type" => "dropByPeriod", "period" => "P3Y"},
        %{"type" => "dropBeforeByPeriod", "period" => "P5Y"},
        %{"type" => "loadByInterval", "interval" => "2020-01-01/2021-01-01T05:00:00-05:00"},
        %{"type" => "dropForever"}
      ]

      # What Druid 38 returns after storing those rules
      stored = [
        %{
          "type" => "loadByPeriod",
          "period" => "P2Y",
          "includeFuture" => true,
          "tieredReplicants" => %{"_default_tier" => 2},
          "useDefaultTierForNull" => true
        },
        %{"type" => "dropByPeriod", "period" => "P3Y", "includeFuture" => true},
        %{"type" => "dropBeforeByPeriod", "period" => "P5Y"},
        %{
          "type" => "loadByInterval",
          "interval" => "2020-01-01T00:00:00.000Z/2021-01-01T10:00:00.000Z",
          "tieredReplicants" => %{"_default_tier" => 2},
          "useDefaultTierForNull" => true
        },
        %{"type" => "dropForever"}
      ]

      assert Retention.normalize(rules) == stored
      assert Retention.normalize(stored) == stored
    end

    test "keeps values that differ from the defaults" do
      rule = %{"type" => "loadByPeriod", "period" => "P1M", "includeFuture" => false}
      assert %{"includeFuture" => false} = hd(Retention.normalize([rule]))
    end

    test "leaves intervals it can't parse alone" do
      rule = %{"type" => "dropByInterval", "interval" => "P1D/2020-01-01"}
      assert [%{"interval" => "P1D/2020-01-01"}] = Retention.normalize([rule])
    end
  end

  describe "sync/2" do
    # A fake Coordinator: `current` is the map Druid returns for all rules.
    defp druid(current, opts \\ []) do
      tiers = Keyword.get(opts, :tiers, ["hot", "_default_tier"])
      fail = Keyword.get(opts, :fail, [])
      test_pid = self()

      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        case {conn.method, conn.path_info} do
          {"GET", ["druid", "coordinator", "v1", "rules"]} ->
            Req.Test.json(conn, current)

          {"GET", ["druid", "coordinator", "v1", "tiers"]} ->
            send(test_pid, :fetched_tiers)
            Req.Test.json(conn, tiers)

          {"POST", ["druid", "coordinator", "v1", "rules", ds]} ->
            send(test_pid, {:set, ds, Jason.decode!(body), conn.req_headers})

            if ds in fail do
              conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "nope"})
            else
              Req.Test.json(conn, %{})
            end
        end
      end
    end

    test "passes :receive_timeout and retry options to each request", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @rules)
      test = self()
      plug = druid(%{})

      # Req runs a :plug in place of any adapter, so this adapter runs it
      adapter = fn request ->
        send(test, {:options, request.options[:receive_timeout], request.options[:max_retries]})
        Req.Plug.run(%{request | options: Map.put(request.options, :plug, plug)})
      end

      opts = opts(dir, adapter: adapter, receive_timeout: 60_000, max_retries: 1)

      assert [{:created, _}] = Retention.sync(TestRepo, opts)

      # Fetching the current rules, then setting the new ones
      assert_received {:options, 60_000, 1}
      assert_received {:options, 60_000, 1}
    end

    defp stored(tier, replicas) do
      [
        %{
          "type" => "loadByPeriod",
          "period" => "P2Y",
          "includeFuture" => true,
          "tieredReplicants" => %{tier => replicas},
          "useDefaultTierForNull" => true
        },
        %{"type" => "dropForever"}
      ]
    end

    test "creates, updates and leaves rules unchanged", %{tmp_dir: dir} do
      for ds <- ["a", "b", "c"], do: write!(dir, "#{ds}.json.eex", @rules)

      current = %{"b" => stored("hot", 1), "c" => stored("hot", 2), "_default" => []}

      assert [
               created: %Rules{data_source: "a"},
               updated: %Rules{data_source: "b"},
               unchanged: %Rules{data_source: "c"}
             ] = Retention.sync(TestRepo, opts(dir, plug: druid(current)))

      assert_received {:set, "a", [%{"tieredReplicants" => %{"hot" => 2}}, _], headers}
      assert {"x-druid-author", "ecto_druid"} in headers
      assert {"x-druid-comment", "Synced from retention template a"} in headers
      assert_received {:set, "b", _, _}
      refute_received {:set, "c", _, _}
    end

    test "a data source with empty rules counts as new", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @rules)

      assert [{:created, _}] = Retention.sync(TestRepo, opts(dir, plug: druid(%{"a" => []})))
    end

    test "dry_run submits nothing", %{tmp_dir: dir} do
      for ds <- ["a", "b", "c"], do: write!(dir, "#{ds}.json.eex", @rules)
      current = %{"b" => stored("hot", 1), "c" => stored("hot", 2)}

      assert [would_create: _, would_update: _, unchanged: _] =
               Retention.sync(TestRepo, opts(dir, plug: druid(current), dry_run: true))

      refute_received {:set, _, _, _}
    end

    test "refuses rules for tiers without Historicals", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @rules)
      write!(dir, "b.json", ~s([{"type": "loadForever"}]))

      assert [{:error, %Rules{data_source: "a"}, error}, {:error, %Rules{data_source: "b"}, _}] =
               Retention.sync(TestRepo, opts(dir, plug: druid(%{}, tiers: ["cold"])))

      assert Exception.message(error) =~ ~s(a loads segments onto unknown tiers ["hot"])
      refute_received {:set, _, _, _}
    end

    test "the :tiers option replaces the live tier list", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @rules)
      plug = druid(%{}, tiers: [])

      assert [{:created, _}] = Retention.sync(TestRepo, opts(dir, plug: plug, tiers: ["hot"]))
      refute_received :fetched_tiers

      assert [{:created, _}] = Retention.sync(TestRepo, opts(dir, plug: plug, tiers: false))
      refute_received :fetched_tiers
    end

    test "prune clears rules of data sources without a template", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @rules)

      current = %{
        "a" => stored("hot", 2),
        "old" => stored("hot", 2),
        "empty" => [],
        "_default" => stored("hot", 2)
      }

      assert [{:unchanged, _}, {:would_clear, "old"}] =
               Retention.sync(
                 TestRepo,
                 opts(dir, plug: druid(current), prune: true, dry_run: true)
               )

      refute_received {:set, _, _, _}

      assert [{:unchanged, _}, {:cleared, "old"}] =
               Retention.sync(TestRepo, opts(dir, plug: druid(current), prune: true))

      assert_received {:set, "old", [], headers}
      assert {"x-druid-comment", "Removed by Druid.Retention: no template"} in headers
    end

    test "prune can't be combined with only", %{tmp_dir: dir} do
      assert_raise ArgumentError, fn ->
        Retention.sync(TestRepo, opts(dir, prune: true, only: ["a"]))
      end
    end

    test "keeps going after a failed request", %{tmp_dir: dir} do
      for ds <- ["a", "b"], do: write!(dir, "#{ds}.json.eex", @rules)

      assert [{:error, %Rules{data_source: "a"}, %Druid.Client.RequestError{}}, {:created, _}] =
               Retention.sync(TestRepo, opts(dir, plug: druid(%{}, fail: ["a"])))
    end
  end
end
