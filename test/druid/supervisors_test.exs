defmodule Druid.SupervisorsTest do
  use ExUnit.Case, async: true
  alias Druid.Supervisors
  alias Druid.Supervisors.Spec
  alias Ecto.Adapters.Druid.TestRepo

  @moduletag :tmp_dir

  @kafka """
  {
    "type": "kafka",
    "spec": {
      "ioConfig": {
        "topic": <%= json @topic %>,
        "consumerProperties": <%= json @kafka.consumer_properties %>,
        "taskCount": <%= @task_count %>
      },
      "tuningConfig": {"type": "kafka", "indexSpec": <%= partial "index_spec" %>},
      "dataSchema": {"dataSource": <%= json @spec_name %>}
    }
  }
  """

  @index_spec """
  {"metricCompression": "lz4", "complexMetricCompression": <%= json @complex_compression %>}
  """

  defp write!(dir, name, contents) do
    path = Path.join(dir, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp base_opts(dir, extra \\ []) do
    Keyword.merge(
      [
        path: dir,
        assigns: %{
          topic: "events",
          task_count: 1,
          complex_compression: "zstd",
          kafka: %{consumer_properties: %{"bootstrap.servers" => "kafka:9092"}}
        }
      ],
      extra
    )
  end

  describe "render/2" do
    test "renders templates with assigns, json and partials", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", @kafka)
      write!(dir, "_index_spec.json.eex", @index_spec)

      assert [%Spec{name: "events", id: "events", spec: spec}] =
               Supervisors.render(TestRepo, base_opts(dir))

      assert spec["spec"]["ioConfig"] == %{
               "topic" => "events",
               "consumerProperties" => %{"bootstrap.servers" => "kafka:9092"},
               "taskCount" => 1
             }

      assert spec["spec"]["tuningConfig"]["indexSpec"] == %{
               "metricCompression" => "lz4",
               "complexMetricCompression" => "zstd"
             }
    end

    test "deep-merges per-spec assigns over global assigns", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", @kafka)
      write!(dir, "_index_spec.json.eex", @index_spec)

      opts =
        base_opts(dir,
          specs: %{
            "events" => %{
              task_count: 4,
              kafka: %{consumer_properties: %{"security.protocol" => "SSL"}}
            }
          }
        )

      [%Spec{spec: spec}] = Supervisors.render(TestRepo, opts)

      assert spec["spec"]["ioConfig"]["taskCount"] == 4

      assert spec["spec"]["ioConfig"]["consumerProperties"] == %{
               "bootstrap.servers" => "kafka:9092",
               "security.protocol" => "SSL"
             }
    end

    test "partials take extra assigns and can live in subdirectories", %{tmp_dir: dir} do
      write!(dir, "shared/_index_spec.json.eex", @index_spec)

      write!(dir, "events.json.eex", """
      {"type": "kafka", "spec": {"dataSchema": {"dataSource": "events"},
        "tuningConfig": {"indexSpec": <%= partial "shared/index_spec", complex_compression: "none" %>}}}
      """)

      [%Spec{spec: spec}] = Supervisors.render(TestRepo, base_opts(dir))
      assert spec["spec"]["tuningConfig"]["indexSpec"]["complexMetricCompression"] == "none"
    end

    test "supports EEx control flow", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", """
      {"type": "kafka", "spec": {"dataSchema": {"dataSource": "events",
        "transformSpec": {"filter": {"type": "and", "fields": [
          <%= if @environment do %>{"type": "selector", "dimension": "environment", "value": <%= json @environment %>},<% end %>
          {"type": "selector", "dimension": "country", "value": "US"}
        ]}}}}}
      """)

      [%Spec{spec: spec}] =
        Supervisors.render(TestRepo, base_opts(dir, assigns: %{environment: nil}))

      assert length(spec["spec"]["dataSchema"]["transformSpec"]["filter"]["fields"]) == 1

      [%Spec{spec: spec}] =
        Supervisors.render(TestRepo, base_opts(dir, assigns: %{environment: "production"}))

      assert [%{"value" => "production"}, _] =
               spec["spec"]["dataSchema"]["transformSpec"]["filter"]["fields"]
    end

    test "names nested templates by relative path and includes plain JSON", %{tmp_dir: dir} do
      write!(dir, "kafka/events.json.eex", @kafka)
      write!(dir, "_index_spec.json.eex", @index_spec)

      write!(
        dir,
        "compaction/events.json",
        ~s({"type": "autocompact", "spec": {"dataSource": "events"}})
      )

      specs = Supervisors.render(TestRepo, base_opts(dir))

      assert [{"compaction/events", "autocompact__events"}, {"kafka/events", "kafka/events"}] ==
               Enum.map(specs, &{&1.name, &1.id})
    end

    test "uses an explicit id when the spec has one", %{tmp_dir: dir} do
      write!(dir, "a.json", ~s({"type": "kafka", "id": "custom", "spec": {}}))
      assert [%Spec{id: "custom"}] = Supervisors.render(TestRepo, path: dir)
    end

    test "renders only the requested specs", %{tmp_dir: dir} do
      write!(dir, "a.json", ~s({"type": "autocompact", "spec": {"dataSource": "a"}}))
      write!(dir, "b.json", ~s({"type": "autocompact", "spec": {"dataSource": "b"}}))

      assert [%Spec{name: "b"}] = Supervisors.render(TestRepo, path: dir, only: ["b"])

      assert_raise Supervisors.Error, ~r/no supervisor templates named: c/, fn ->
        Supervisors.render(TestRepo, path: dir, only: ["b", "c"])
      end
    end

    test "raises on a missing assign", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", ~s({"topic": <%= json @tpoic %>}))

      assert_raise Supervisors.Error, ~r/failed to render events: assign @tpoic is not set/, fn ->
        Supervisors.render(TestRepo, base_opts(dir))
      end
    end

    test "raises on a missing partial", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", ~s({"a": <%= partial "nope" %>}))

      assert_raise Supervisors.Error, ~r/partial "nope" not found/, fn ->
        Supervisors.render(TestRepo, path: dir)
      end
    end

    test "raises on invalid JSON", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", ~s({"topic": <%= @topic %>}))

      assert_raise Supervisors.Error, ~r/events rendered invalid JSON/, fn ->
        Supervisors.render(TestRepo, base_opts(dir))
      end
    end

    test "points at invalid JSON without showing the rendered spec", %{tmp_dir: dir} do
      write!(dir, "events.json.eex", """
      {
        "password": <%= json @password %>,
        "topic": "events",
      }
      """)

      error =
        assert_raise Supervisors.Error, fn ->
          Supervisors.render(TestRepo, path: dir, assigns: %{password: "hunter2"})
        end

      assert error.message =~ "events rendered invalid JSON at line 4, column 1: unexpected byte"
      refute error.message =~ "hunter2"
    end

    test "raises when a spec has no supervisor id", %{tmp_dir: dir} do
      write!(dir, "events.json", ~s({"type": "kafka", "spec": {}}))

      assert_raise Supervisors.Error, ~r/events has no supervisor ID/, fn ->
        Supervisors.render(TestRepo, path: dir)
      end
    end

    test "raises when templates share a supervisor id", %{tmp_dir: dir} do
      write!(dir, "a.json", ~s({"type": "autocompact", "spec": {"dataSource": "x"}}))
      write!(dir, "b.json", ~s({"type": "autocompact", "spec": {"dataSource": "x"}}))

      assert_raise Supervisors.Error, ~r/autocompact__x \(a, b\)/, fn ->
        Supervisors.render(TestRepo, path: dir)
      end
    end

    test "raises when the templates directory doesn't exist", %{tmp_dir: dir} do
      assert_raise Supervisors.Error, ~r/directory not found/, fn ->
        Supervisors.render(TestRepo, path: Path.join(dir, "missing"))
      end
    end
  end

  describe "sync/2" do
    # A fake Overlord: `existing` are the running supervisor IDs and `unchanged`
    # are the IDs Druid reports as unmodified when resubmitted.
    defp druid(existing, opts \\ []) do
      unchanged = Keyword.get(opts, :unchanged, [])
      fail = Keyword.get(opts, :fail, [])
      test_pid = self()

      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:druid, conn.method, conn.request_path, conn.query_string, body})

        case {conn.method, conn.path_info} do
          {"GET", ["druid", "indexer", "v1", "supervisor"]} ->
            Req.Test.json(conn, existing)

          {"POST", ["druid", "indexer", "v1", "supervisor"]} ->
            id = Supervisors.supervisor_id(Jason.decode!(body))

            if id in fail do
              conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad spec"})
            else
              modified = id not in unchanged
              Req.Test.json(conn, %{"id" => id, "modified" => modified, "restarted" => modified})
            end

          {"POST", ["druid", "indexer", "v1", "supervisor", id, "terminate"]} ->
            Req.Test.json(conn, %{"id" => id})
        end
      end
    end

    defp write_specs!(dir, data_sources) do
      for ds <- data_sources do
        write!(dir, "#{ds}.json", ~s({"type": "autocompact", "spec": {"dataSource": "#{ds}"}}))
      end
    end

    test "reports created, updated and unchanged supervisors", %{tmp_dir: dir} do
      write_specs!(dir, ["a", "b", "c"])

      results =
        Supervisors.sync(TestRepo,
          path: dir,
          plug: druid(["autocompact__b", "autocompact__c"], unchanged: ["autocompact__c"])
        )

      assert [
               created: %Spec{id: "autocompact__a"},
               updated: %Spec{id: "autocompact__b"},
               unchanged: %Spec{id: "autocompact__c"}
             ] = results

      assert_received {:druid, "POST", "/druid/indexer/v1/supervisor",
                       "skipRestartIfUnmodified=true", _}
    end

    test "uses the supervisors host and port, falling back to the repo's", %{tmp_dir: dir} do
      write_specs!(dir, ["a"])
      test_pid = self()

      plug = fn conn ->
        send(test_pid, {:host, conn.host, conn.port})
        druid([]).(conn)
      end

      Supervisors.sync(TestRepo, path: dir, plug: plug, port: 8888)
      assert_received {:host, "localhost", 8888}
    end

    test "restart: true forces a restart", %{tmp_dir: dir} do
      write_specs!(dir, ["a"])
      test_pid = self()

      # Druid reports a forced restart of an unchanged spec as modified: false
      plug = fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, ["autocompact__a"])

          "POST" ->
            send(test_pid, {:query, conn.query_string})

            Req.Test.json(conn, %{
              "id" => "autocompact__a",
              "modified" => false,
              "restarted" => true
            })
        end
      end

      assert [{:restarted, _}] = Supervisors.sync(TestRepo, path: dir, plug: plug, restart: true)
      assert_received {:query, "skipRestartIfUnmodified=false"}
    end

    test "dry_run submits nothing", %{tmp_dir: dir} do
      write_specs!(dir, ["a", "b"])

      results =
        Supervisors.sync(TestRepo,
          path: dir,
          plug: druid(["autocompact__b", "other"]),
          dry_run: true,
          prune: true
        )

      assert [
               {:would_create, %Spec{id: "autocompact__a"}},
               {:would_update, %Spec{id: "autocompact__b"}},
               {:would_terminate, "other"}
             ] = results

      refute_received {:druid, "POST", _, _, _}
    end

    test "prune terminates supervisors without a template", %{tmp_dir: dir} do
      write_specs!(dir, ["a"])

      results =
        Supervisors.sync(TestRepo,
          path: dir,
          plug: druid(["autocompact__a", "z", "y"]),
          prune: true
        )

      assert [{:updated, _}, {:terminated, "y"}, {:terminated, "z"}] = results
      assert_received {:druid, "POST", "/druid/indexer/v1/supervisor/y/terminate", _, _}
    end

    test "prune can't be combined with only", %{tmp_dir: dir} do
      assert_raise ArgumentError, fn ->
        Supervisors.sync(TestRepo, path: dir, only: ["a"], prune: true)
      end
    end

    test "keeps going after a failed submission", %{tmp_dir: dir} do
      write_specs!(dir, ["a", "b"])

      results = Supervisors.sync(TestRepo, path: dir, plug: druid([], fail: ["autocompact__a"]))

      assert [{:error, %Spec{id: "autocompact__a"}, %Druid.Client.RequestError{}}, {:created, _}] =
               results
    end
  end
end
