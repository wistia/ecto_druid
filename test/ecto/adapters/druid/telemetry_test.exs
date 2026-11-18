defmodule Ecto.Adapters.Druid.TelemetryTest do
  use ExUnit.Case
  import Ecto.Query
  import ExUnit.CaptureLog
  alias Ecto.Adapters.Druid.{NativeQueryError, TestRepo, Wikipedia}
  alias Druid.Client.RequestError

  @event [:ecto, :adapters, :druid, :test_repo, :query]

  setup do
    start_supervised!(TestRepo)
    test = self()
    handler = "telemetry-test-#{inspect(test)}"

    :telemetry.attach(handler, @event, &__MODULE__.handle_event/4, test)

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  def handle_event(event, measurements, metadata, test) do
    send(test, {:telemetry, event, measurements, metadata})
  end

  # Answers every request with `status` and `response`, and sends each
  # request body to the test process.
  defp druid(response, status \\ 200) do
    test = self()

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.method, conn.request_path, decode(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(response))
    end
  end

  defp decode(""), do: nil
  defp decode(body), do: Jason.decode!(body)

  defp pages_query, do: from(w in Wikipedia, where: w.added > ^10, select: w.page)

  describe "SQL queries" do
    test "emit the repo's query event" do
      assert TestRepo.all(pages_query(), plug: druid([["a"], ["b"]])) == ["a", "b"]

      assert_received {:request, "POST", "/druid/v2/sql", %{"context" => context}}
      assert_received {:telemetry, @event, measurements, metadata}

      assert %{query_time: query_time, decode_time: decode_time, total_time: total_time} =
               measurements

      assert total_time == query_time + decode_time
      assert decode_time >= 0

      assert %{
               type: :druid_sql_query,
               repo: TestRepo,
               source: "wikipedia",
               params: [%{type: "BIGINT", value: 10}],
               cast_params: [10],
               result: {:ok, %{num_rows: 2, rows: [["a"], ["b"]]}},
               deep_storage: nil,
               stacktrace: nil,
               options: []
             } = metadata

      assert metadata.query =~ ~s(FROM "wikipedia")
      assert metadata.query_id == context["sqlQueryId"]
      assert {:ok, _} = Ecto.UUID.cast(metadata.query_id)
    end

    test "keep a sqlQueryId given in the context" do
      TestRepo.all(pages_query(), plug: druid([]), context: %{sqlQueryId: "mine"})

      assert_received {:request, _, _, %{"context" => %{"sqlQueryId" => "mine"}}}
      assert_received {:telemetry, @event, _, %{query_id: "mine"}}
    end

    test "emit an error result and still raise when Druid fails" do
      assert_raise RequestError, fn ->
        TestRepo.all(pages_query(), plug: druid(%{"error" => "bad"}, 400))
      end

      assert_received {:telemetry, @event, %{total_time: _}, %{result: {:error, error}}}
      assert %RequestError{status: 400} = error
    end

    test "pass :telemetry_options through and honor :telemetry_event" do
      TestRepo.all(pages_query(), plug: druid([]), telemetry_options: [name: :pages])
      assert_received {:telemetry, @event, _, %{options: [name: :pages]}}

      TestRepo.all(pages_query(), plug: druid([]), telemetry_event: nil)
      refute_received {:telemetry, _, _, _}
    end

    test "emit once a stream is enumerated" do
      stream = TestRepo.stream(pages_query(), plug: druid([["a"]]))
      refute_received {:telemetry, _, _, _}

      assert Enum.to_list(stream) == ["a"]
      assert_received {:telemetry, @event, _, %{result: {:ok, %{num_rows: 1}}}}
    end

    test "include the stacktrace when asked" do
      TestRepo.all(pages_query(), plug: druid([]), stacktrace: true)
      assert_received {:telemetry, @event, _, %{stacktrace: [_ | _]}}
    end
  end

  describe "deep storage queries" do
    defp statements(test) do
      fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)
        send(test, {:request, conn.method, conn.request_path, nil})

        response =
          case {conn.method, conn.request_path} do
            {"POST", "/druid/v2/sql/statements"} ->
              %{"queryId" => "q1", "state" => "RUNNING"}

            {"GET", "/druid/v2/sql/statements/q1"} ->
              %{
                "queryId" => "q1",
                "state" => "SUCCESS",
                "result" => %{"numTotalRows" => 2, "pages" => [%{"id" => 0, "numRows" => 2}]}
              }

            {"GET", "/druid/v2/sql/statements/q1/results"} ->
              [["a"], ["b"]]
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
      end
    end

    test "emit one event for the statement and its results" do
      opts = [
        plug: statements(self()),
        deep_storage: [poll_interval: 1],
        context: %{sqlQueryId: "q1"}
      ]

      assert TestRepo.all(pages_query(), opts) == ["a", "b"]

      assert_received {:telemetry, @event, _, metadata}
      assert %{query_id: "q1", deep_storage: [poll_interval: 1]} = metadata
      assert metadata.result == {:ok, %{num_rows: 2, rows: [["a"], ["b"]]}}
    end

    test "emit when a stream's statement finishes, before its pages are read" do
      opts = [
        plug: statements(self()),
        deep_storage: [poll_interval: 1],
        context: %{sqlQueryId: "q1"}
      ]

      stream = TestRepo.stream(pages_query(), opts)
      assert Enum.to_list(stream) == ["a", "b"]

      assert_received {:telemetry, @event, _, %{result: {:ok, %{num_rows: 2, rows: nil}}}}
    end
  end

  describe "native queries" do
    @topn %{
      queryType: "topN",
      dataSource: "wikipedia",
      dimension: "page",
      aggregations: [%{type: "count", name: "rows"}]
    }

    @topn_results [
      %{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => [%{"page" => "a", "rows" => 2}]}
    ]

    test "emit the repo's query event" do
      query = Map.put(@topn, :context, %{queryId: "n1"})
      assert {:ok, rows} = TestRepo.native_query(query, plug: druid(@topn_results))

      assert_received {:telemetry, @event, %{decode_time: _}, metadata}

      assert %{
               type: :druid_native_query,
               repo: TestRepo,
               source: "wikipedia",
               query_id: "n1",
               params: nil,
               native_query: %{"queryType" => "topN"},
               result: {:ok, %{num_rows: 1, rows: ^rows}}
             } = metadata

      assert Jason.decode!(metadata.query)["queryType"] == "topN"
    end

    test "emit an error result" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 400, ~s({"error":"bad"})) end
      assert {:error, _} = TestRepo.native_query(@topn, plug: plug)
      assert_received {:telemetry, @event, _, %{result: {:error, %NativeQueryError{}}}}
    end

    test "report a union's source as nil" do
      query = %{@topn | dataSource: %{type: "union", dataSources: ["a", "b"]}}
      TestRepo.native_query(query, plug: druid(@topn_results))
      assert_received {:telemetry, @event, _, %{source: nil}}
    end
  end

  describe "insert_all/3" do
    defmodule Event do
      use Ecto.Schema
      @primary_key false
      schema "events" do
        field :time, :utc_datetime, source: :__time
        field :channel, :string
      end
    end

    defp tasks do
      fn conn ->
        {:ok, _body, conn} = Plug.Conn.read_body(conn)

        response =
          case conn.request_path do
            "/druid/v2/sql/task" ->
              %{"taskId" => "t1", "state" => "RUNNING"}

            "/druid/indexer/v1/task/t1/status" ->
              %{"status" => %{"id" => "t1", "status" => "SUCCESS"}}

            "/druid/indexer/v1/task/t1/reports" ->
              %{}
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(response))
      end
    end

    test "emits one event for submitting and awaiting the task" do
      rows = [[time: ~U[2026-11-01 00:00:00Z], channel: "#en"]]

      assert {1, nil} =
               TestRepo.insert_all(Event, rows,
                 partitioned_by: :day,
                 plug: tasks(),
                 poll_interval: 1
               )

      assert_received {:telemetry, @event, _, metadata}
      assert %{type: :druid_sql_query, source: "events", result: {:ok, %{num_rows: 1}}} = metadata
      assert metadata.query =~ ~s(INSERT INTO "events")
    end
  end

  describe "logging" do
    test "logs the query at the level given" do
      log = capture_log(fn -> TestRepo.all(pages_query(), plug: druid([]), log: :info) end)

      assert log =~ ~s(QUERY OK source="wikipedia" db=)
      assert log =~ ~s(FROM "wikipedia")
      assert log =~ "[10]"
    end

    test "logs errors" do
      log =
        capture_log(fn ->
          assert_raise RequestError, fn ->
            TestRepo.all(pages_query(), plug: druid(%{}, 500), log: :info)
          end
        end)

      assert log =~ "QUERY ERROR"
    end

    test "points at the caller with a stacktrace" do
      log =
        capture_log(fn ->
          _ = TestRepo.all(pages_query(), plug: druid([]), log: :info, stacktrace: true)
          :ok
        end)

      assert log =~
               ~r/↳ .*Ecto.Adapters.Druid.TelemetryTest.*, at: test\/ecto\/adapters\/druid\/telemetry_test.exs:\d+/
    end

    test "logs nothing with log: false" do
      log = capture_log(fn -> TestRepo.all(pages_query(), plug: druid([]), log: false) end)
      refute log =~ "QUERY"
    end

    test "logs native queries as JSON" do
      log =
        capture_log(fn ->
          TestRepo.native_query(@topn, plug: druid(@topn_results), log: :info)
        end)

      assert log =~ ~s("queryType":"topN")
    end
  end
end
