defmodule Druid.CompactionTest do
  use ExUnit.Case, async: true
  alias Druid.Compaction
  alias Druid.Compaction.Config
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  @template """
  {
    "skipOffsetFromLatest": "P1D",
    "tuningConfig": {"partitionsSpec": {"type": "dynamic", "maxRowsPerSegment": <%= @rows %>}}
  }
  """

  defp write!(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp opts(dir, extra \\ []) do
    Keyword.merge([path: dir, assigns: %{rows: 5_000_000}], extra)
  end

  # What Druid returns for a config rendered from @template
  defp stored(ds, rows) do
    %{
      "type" => "inline",
      "dataSource" => ds,
      "taskPriority" => 25,
      "inputSegmentSizeBytes" => 100_000_000_000_000,
      "maxRowsPerSegment" => nil,
      "skipOffsetFromLatest" => "P1D",
      "tuningConfig" => %{
        "maxRowsInMemory" => nil,
        "partitionsSpec" => %{
          "type" => "dynamic",
          "maxRowsPerSegment" => rows,
          "maxTotalRows" => nil
        },
        "type" => "index_parallel",
        "forceGuaranteedRollup" => false
      },
      "granularitySpec" => nil,
      "metricsSpec" => nil,
      "engine" => nil
    }
  end

  describe "render/2" do
    test "names the data source after the file and adds it to the config", %{tmp_dir: dir} do
      write!(dir, "nested/page_views.json.eex", @template)

      assert [%Config{name: "nested/page_views", data_source: "page_views", config: config}] =
               Compaction.render(TestRepo, opts(dir))

      assert config["dataSource"] == "page_views"
      assert config["tuningConfig"]["partitionsSpec"]["maxRowsPerSegment"] == 5_000_000
    end

    test "keeps an explicit dataSource", %{tmp_dir: dir} do
      write!(dir, "a.json", ~s({"dataSource": "other"}))
      assert [%Config{data_source: "other"}] = Compaction.render(TestRepo, opts(dir))
    end

    test "can use the schema helpers", %{tmp_dir: dir} do
      write!(dir, "page_views.json.eex", """
      {"metricsSpec": <%= metrics_spec Ecto.Adapters.Druid.PageViews, combining: true %>}
      """)

      assert [%Config{config: %{"metricsSpec" => [%{"type" => "longSum"} | _]}}] =
               Compaction.render(TestRepo, opts(dir))
    end

    test "raises when a template doesn't render an object", %{tmp_dir: dir} do
      write!(dir, "a.json", "[]")

      assert_raise Compaction.Error, ~r/a must render a JSON object/, fn ->
        Compaction.render(TestRepo, opts(dir))
      end
    end

    test "raises when two templates configure the same data source", %{tmp_dir: dir} do
      write!(dir, "a.json", "{}")
      write!(dir, "b.json", ~s({"dataSource": "a"}))

      assert_raise Compaction.Error, ~r/same data source: a \(a, b\)/, fn ->
        Compaction.render(TestRepo, opts(dir))
      end
    end
  end

  describe "matches?/2" do
    test "ignores settings only Druid has" do
      rendered = %{
        "skipOffsetFromLatest" => "P1D",
        "tuningConfig" => %{"maxNumConcurrentSubTasks" => 2}
      }

      stored = %{
        "skipOffsetFromLatest" => "P1D",
        "taskPriority" => 25,
        "tuningConfig" => %{"maxNumConcurrentSubTasks" => 2, "type" => "index_parallel"}
      }

      assert Compaction.matches?(rendered, stored)

      refute Compaction.matches?(
               put_in(rendered["tuningConfig"]["maxNumConcurrentSubTasks"], 3),
               stored
             )
    end

    test "null matches a missing or null setting" do
      assert Compaction.matches?(%{"engine" => nil}, %{})
      assert Compaction.matches?(%{"engine" => nil}, %{"engine" => nil})
      refute Compaction.matches?(%{"engine" => nil}, %{"engine" => "native"})
      refute Compaction.matches?(%{"engine" => "native"}, %{})
    end

    test "lists must match element by element" do
      assert Compaction.matches?([%{"name" => "a"}], [%{"name" => "a", "x" => 1}])
      refute Compaction.matches?([%{"name" => "a"}], [%{"name" => "a"}, %{"name" => "b"}])
      refute Compaction.matches?([1, 2], [2, 1])
    end

    test "a string dimension matches the object Druid expands it to" do
      stored = %{
        "dimensions" => [
          %{"type" => "string", "name" => "a", "multiValueHandling" => "SORTED_ARRAY"},
          %{"type" => "long", "name" => "b"}
        ]
      }

      assert Compaction.matches?(
               %{"dimensions" => ["a", %{"type" => "long", "name" => "b"}]},
               stored
             )

      refute Compaction.matches?(%{"dimensions" => ["a", "b"]}, stored)
    end
  end

  describe "sync/2" do
    # A fake Overlord. `current` is the list of stored compaction configs.
    defp druid(current, opts \\ []) do
      fail = Keyword.get(opts, :fail, [])
      test_pid = self()

      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        path = "/druid/indexer/v1/compaction/config/datasources"

        case {conn.method, conn.request_path} do
          {"GET", ^path} ->
            Req.Test.json(conn, %{"compactionConfigs" => current})

          {"POST", ^path <> "/" <> ds} ->
            send(test_pid, {:set, ds, Jason.decode!(body), conn.req_headers})

            if ds in fail do
              conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad"})
            else
              Req.Test.json(conn, %{"success" => true})
            end

          {"DELETE", ^path <> "/" <> ds} ->
            send(test_pid, {:delete, ds, conn.req_headers})
            Req.Test.json(conn, %{"success" => true})
        end
      end
    end

    test "creates, updates and leaves configs unchanged", %{tmp_dir: dir} do
      for ds <- ["a", "b", "c"], do: write!(dir, "#{ds}.json.eex", @template)
      current = [stored("b", 1_000_000), stored("c", 5_000_000)]

      assert [
               created: %Config{data_source: "a"},
               updated: %Config{data_source: "b"},
               unchanged: %Config{data_source: "c"}
             ] = Compaction.sync(TestRepo, opts(dir, plug: druid(current)))

      assert_received {:set, "a", %{"dataSource" => "a"}, headers}
      assert {"x-druid-author", "ecto_druid"} in headers
      assert {"x-druid-comment", "Synced from compaction template a"} in headers
      assert_received {:set, "b", _, _}
      refute_received {:set, "c", _, _}
    end

    test "force submits unchanged configs", %{tmp_dir: dir} do
      write!(dir, "c.json.eex", @template)

      assert [{:updated, _}] =
               Compaction.sync(
                 TestRepo,
                 opts(dir, plug: druid([stored("c", 5_000_000)]), force: true)
               )

      assert_received {:set, "c", _, _}
    end

    test "dry_run submits nothing", %{tmp_dir: dir} do
      for ds <- ["a", "b", "c"], do: write!(dir, "#{ds}.json.eex", @template)
      current = [stored("b", 1_000_000), stored("c", 5_000_000)]

      assert [would_create: _, would_update: _, unchanged: _] =
               Compaction.sync(TestRepo, opts(dir, plug: druid(current), dry_run: true))

      refute_received {:set, _, _, _}
    end

    test "prune deletes configs of data sources without a template", %{tmp_dir: dir} do
      write!(dir, "a.json.eex", @template)
      current = [stored("a", 5_000_000), stored("old", 1)]

      assert [{:unchanged, _}, {:would_delete, "old"}] =
               Compaction.sync(
                 TestRepo,
                 opts(dir, plug: druid(current), prune: true, dry_run: true)
               )

      refute_received {:delete, _, _}

      assert [{:unchanged, _}, {:deleted, "old"}] =
               Compaction.sync(TestRepo, opts(dir, plug: druid(current), prune: true))

      assert_received {:delete, "old", headers}
      assert {"x-druid-comment", "Removed by Druid.Compaction: no template"} in headers
    end

    test "prune can't be combined with only", %{tmp_dir: dir} do
      assert_raise ArgumentError, fn ->
        Compaction.sync(TestRepo, opts(dir, prune: true, only: ["a"]))
      end
    end

    test "keeps going after a failed request", %{tmp_dir: dir} do
      for ds <- ["a", "b"], do: write!(dir, "#{ds}.json.eex", @template)

      assert [{:error, %Config{data_source: "a"}, %Druid.Client.RequestError{}}, {:created, _}] =
               Compaction.sync(TestRepo, opts(dir, plug: druid([], fail: ["a"])))
    end
  end
end
