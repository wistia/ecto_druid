defmodule Ecto.Adapters.Druid.IngestTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.TestRepo

  defmodule Event do
    use Ecto.Schema
    @primary_key false
    schema "events" do
      field :time, :utc_datetime, source: :__time
      field :channel, :string
      field :count, :integer
    end
  end

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  @report %{
    "multiStageQuery" => %{
      "payload" => %{
        "counters" => %{
          "0" => %{"0" => %{"output" => %{"rows" => [3]}}},
          "1" => %{
            "0" => %{"segmentGenerationProgress" => %{"rowsPushed" => 2}},
            "1" => %{"segmentGenerationProgress" => %{"rowsPushed" => 1}}
          }
        }
      }
    }
  }

  # Answers the count, submit, status and report requests of a successful task and
  # records what was asked.
  defp druid(opts \\ []) do
    test = self()
    status = Keyword.get(opts, :status, "SUCCESS")
    report = Keyword.get(opts, :report, @report)
    count = Keyword.get(opts, :count, 4)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = if body == "", do: nil, else: Jason.decode!(body)
      send(test, {:request, conn.method, conn.request_path, body})

      {code, response} =
        case conn.request_path do
          "/druid/v2/sql" ->
            {200, [[count]]}

          "/druid/v2/sql/task" ->
            {200, %{"taskId" => "t1", "state" => "RUNNING"}}

          "/druid/indexer/v1/task/t1/status" ->
            {200, %{"status" => %{"id" => "t1", "status" => status, "errorMsg" => "boom"}}}

          "/druid/indexer/v1/task/t1/reports" ->
            {200, report}
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(code, Jason.encode!(response))
    end

    [plug: plug, poll_interval: 1]
  end

  # Pairs each row of an INSERT ... VALUES statement with its column names,
  # taking a parameter for each ? and nil for each NULL
  defp sent_rows(sql, params) do
    [_, values, columns] = Regex.run(~r/\(VALUES (.+)\) AS "input"\((.+?)\)/, sql)
    columns = columns |> String.split(",") |> Enum.map(&String.trim(&1, ~s(")))

    {rows, []} =
      ~r/\(([^()]+)\)/
      |> Regex.scan(values, capture: :all_but_first)
      |> Enum.map_reduce(params, fn [row], params ->
        {values, params} =
          row
          |> String.split(", ")
          |> Enum.map_reduce(params, fn
            "?", [param | params] -> {param, params}
            "NULL", params -> {nil, params}
          end)

        {columns |> Enum.zip(values) |> Map.new(), params}
      end)

    rows
  end

  defp submitted do
    assert_received {:request, "POST", "/druid/v2/sql/task", body}
    body
  end

  describe "insert_all/3 with rows" do
    test "inserts the rows with VALUES and returns the rows written" do
      rows = [
        %{time: ~U[2026-01-01 00:00:00Z], channel: "#en", count: 1},
        %{time: ~U[2026-01-01 01:00:00Z], channel: nil, count: 2}
      ]

      assert {3, nil} = TestRepo.insert_all(Event, rows, [partitioned_by: :day] ++ druid())

      %{"query" => sql, "parameters" => params} = submitted()

      assert sql =~
               ~r{^INSERT INTO "events" SELECT \* FROM \(VALUES \(.+\), \(.+\)\) AS "input"\(.+\) PARTITIONED BY 'DAY'$}

      # Columns are in Ecto's header order, which follows map key order, so
      # check each row's values by column
      assert sent_rows(sql, params) == [
               %{
                 "__time" => %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00Z"},
                 "channel" => %{"type" => "VARCHAR", "value" => "#en"},
                 "count" => %{"type" => "BIGINT", "value" => 1}
               },
               %{
                 "__time" => %{"type" => "TIMESTAMP", "value" => "2026-01-01T01:00:00Z"},
                 "channel" => nil,
                 "count" => %{"type" => "BIGINT", "value" => 2}
               }
             ]
    end

    test "sends placeholders once for each row that uses them" do
      rows = [
        %{time: {:placeholder, :time}, channel: "#en"},
        %{time: {:placeholder, :time}, channel: "#fr"}
      ]

      opts = [partitioned_by: :hour, placeholders: %{time: ~U[2026-01-01 00:00:00Z]}]
      TestRepo.insert_all(Event, rows, opts ++ druid())

      %{"query" => sql, "parameters" => params} = submitted()

      assert sql |> sent_rows(params) |> Enum.map(&Map.new(&1, fn {k, v} -> {k, v["value"]} end)) ==
               [
                 %{"__time" => "2026-01-01T00:00:00Z", "channel" => "#en"},
                 %{"__time" => "2026-01-01T00:00:00Z", "channel" => "#fr"}
               ]
    end

    test "adds CLUSTERED BY and the query context" do
      TestRepo.insert_all(
        "events",
        [%{__time: ~U[2026-01-01 00:00:00Z], channel: "#en"}],
        [partitioned_by: "PT6H", clustered_by: [:channel], context: %{maxNumTasks: 3}] ++ druid()
      )

      %{"query" => sql, "context" => context} = submitted()
      assert sql =~ ~s{ PARTITIONED BY 'PT6H' CLUSTERED BY "channel"}
      assert context["maxNumTasks"] == 3
    end

    test "replaces all data with overwrite: :all" do
      TestRepo.insert_all(
        Event,
        [%{time: ~U[2026-01-01 00:00:00Z]}],
        [partitioned_by: :all, overwrite: :all] ++ druid()
      )

      %{"query" => sql} = submitted()
      assert sql =~ ~r/^REPLACE INTO "events" OVERWRITE ALL SELECT \* FROM /
      assert sql =~ ~r/ PARTITIONED BY ALL TIME$/
    end

    test "replaces an interval, sending its bounds first" do
      for interval <- [
            Ecto.Druid.Interval.new(~D[2026-01-01], ~D[2026-01-02]),
            {~N[2026-01-01 00:00:00], ~N[2026-01-02 00:00:00]},
            "2026-01-01/2026-01-02"
          ] do
        TestRepo.insert_all(
          Event,
          [%{channel: "#en"}],
          [partitioned_by: :day, overwrite: interval] ++ druid()
        )

        %{"query" => sql, "parameters" => params} = submitted()

        assert sql =~
                 ~s{REPLACE INTO "events" OVERWRITE WHERE "__time" >= ? AND "__time" < ? SELECT}

        assert params == [
                 %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00"},
                 %{"type" => "TIMESTAMP", "value" => "2026-01-02T00:00:00"},
                 %{"type" => "VARCHAR", "value" => "#en"}
               ]
      end
    end

    test "falls back to the number of rows when the report has no counters" do
      assert {1, nil} =
               TestRepo.insert_all(
                 Event,
                 [%{channel: "#en"}],
                 [partitioned_by: :day] ++ druid(report: %{})
               )
    end

    test "raises when the task fails" do
      assert_raise Druid.Tasks.Error, ~r/task t1 failed: boom/, fn ->
        TestRepo.insert_all(
          Event,
          [%{channel: "#en"}],
          [partitioned_by: :day] ++ druid(status: "FAILED")
        )
      end
    end
  end

  describe "insert_all/3 with a query" do
    test "inserts the query's rows, naming its columns" do
      query =
        from w in "wikipedia",
          where: w.channel == ^"#en",
          select: %{__time: w.__time, channel: w.channel, count: w.added}

      assert {3, nil} = TestRepo.insert_all("events", query, [partitioned_by: :day] ++ druid())

      %{"query" => sql, "parameters" => params} = submitted()

      assert sql ==
               ~s{INSERT INTO "events" SELECT * FROM (SELECT w0."__time", w0."channel", } <>
                 ~s{w0."added" FROM "wikipedia" AS w0 } <>
                 ~s{WHERE (w0."channel" = ?)) AS "input"("__time","channel","count") } <>
                 ~s{PARTITIONED BY 'DAY'}

      assert params == [%{"type" => "VARCHAR", "value" => "#en"}]
    end
  end

  describe "insert_all/3 errors" do
    test "needs :partitioned_by" do
      assert_raise ArgumentError, ~r/:partitioned_by/, fn ->
        TestRepo.insert_all(Event, [%{channel: "#en"}], druid())
      end
    end

    test "rejects an unknown :partitioned_by" do
      assert_raise ArgumentError, ~r/:partitioned_by must be/, fn ->
        TestRepo.insert_all(Event, [%{channel: "#en"}], [partitioned_by: :fortnight] ++ druid())
      end
    end

    test "rejects :on_conflict and :returning" do
      assert_raise ArgumentError, ~r/:on_conflict/, fn ->
        TestRepo.insert_all(
          Event,
          [%{channel: "#en"}],
          [partitioned_by: :day, on_conflict: :nothing] ++ druid()
        )
      end

      assert_raise ArgumentError, ~r/:returning/, fn ->
        TestRepo.insert_all(
          Event,
          [%{channel: "#en"}],
          [partitioned_by: :day, returning: [:channel]] ++ druid()
        )
      end
    end

    test "needs dates or date-times to overwrite an interval" do
      assert_raise ArgumentError, ~r/:overwrite needs an interval with date/, fn ->
        TestRepo.insert_all(
          Event,
          [%{channel: "#en"}],
          [partitioned_by: :day, overwrite: Ecto.Druid.Interval.last(day: 1)] ++ druid()
        )
      end
    end

    test "sends nothing to Druid when the options are invalid" do
      catch_error(TestRepo.insert_all(Event, [%{channel: "#en"}], druid()))
      refute_received {:request, _, _, _}
    end
  end

  describe "other writes" do
    test "insert explains to use insert_all" do
      assert_raise ArgumentError, ~r/insert_all/, fn -> TestRepo.insert(%Event{}) end
    end

    test "update_all raises Ecto.QueryError" do
      assert_raise Ecto.QueryError, ~r/doesn't support update_all/, fn ->
        TestRepo.update_all(Event, set: [channel: "#fr"])
      end
    end
  end

  describe "delete_all/2" do
    defp counted do
      assert_received {:request, "POST", "/druid/v2/sql", body}
      body
    end

    test "rewrites the interval without the matching rows and returns how many matched" do
      query = from e in Event, where: e.channel == ^"#en"

      assert {4, nil} =
               TestRepo.delete_all(
                 query,
                 [interval: "2026-01-01/2026-01-02", partitioned_by: :day] ++ druid()
               )

      start = %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00"}
      stop = %{"type" => "TIMESTAMP", "value" => "2026-01-02T00:00:00"}
      channel = %{"type" => "VARCHAR", "value" => "#en"}

      # Rows are counted before they're deleted
      %{"query" => count_sql, "parameters" => count_params, "context" => context} = counted()

      assert count_sql ==
               ~s{SELECT count(*) FROM "events" AS e0 } <>
                 ~s{WHERE e0."__time" >= ? AND e0."__time" < ? AND ((e0."channel" = ?))}

      assert count_params == [start, stop, channel]
      %{"query" => sql, "parameters" => params, "context" => task_context} = submitted()

      # The count is its own query, so it doesn't take the task's query id
      assert context["sqlQueryId"] != task_context["sqlQueryId"]

      # IS NOT TRUE keeps the rows the condition is NULL for
      assert sql ==
               ~s{REPLACE INTO "events" OVERWRITE WHERE "__time" >= ? AND "__time" < ? } <>
                 ~s{SELECT * FROM "events" AS e0 } <>
                 ~s{WHERE e0."__time" >= ? AND e0."__time" < ? AND ((e0."channel" = ?)) IS NOT TRUE } <>
                 ~s{PARTITIONED BY 'DAY'}

      assert params == [start, stop, start, stop, channel]
    end

    test "combines where clauses" do
      query =
        from e in "events",
          where: e.channel == "#en",
          or_where: e.count > ^10,
          where: not is_nil(e.channel)

      TestRepo.delete_all(query, [interval: :all, partitioned_by: :day] ++ druid())

      assert %{"query" => sql, "parameters" => [%{"value" => 10}]} = submitted()

      assert sql =~
               ~s{WHERE ((((e0."channel" = '#en')) OR (e0."count" > ?)) AND (NOT (e0."channel" IS NULL))) IS NOT TRUE }
    end

    test "deletes every row in the interval without a where clause" do
      assert {4, nil} =
               TestRepo.delete_all(
                 Event,
                 [interval: {~D[2026-01-01], ~D[2026-01-02]}, partitioned_by: :day] ++ druid()
               )

      assert %{"query" => count_sql} = counted()

      assert count_sql ==
               ~s{SELECT count(*) FROM "events" AS e0 WHERE e0."__time" >= ? AND e0."__time" < ?}

      assert %{"query" => sql, "parameters" => [_, _, _, _]} = submitted()
      assert sql =~ ~s{AS e0 WHERE e0."__time" >= ? AND e0."__time" < ? AND FALSE PARTITIONED BY}
    end

    test "rewrites every time chunk with interval: :all" do
      query = from e in Event, where: e.channel == "#en"

      TestRepo.delete_all(
        query,
        [interval: :all, partitioned_by: :day, clustered_by: [:channel]] ++ druid()
      )

      assert %{"query" => count_sql, "parameters" => []} = counted()
      assert count_sql == ~s{SELECT count(*) FROM "events" AS e0 WHERE ((e0."channel" = '#en'))}

      assert %{"query" => sql, "parameters" => []} = submitted()

      assert sql ==
               ~s{REPLACE INTO "events" OVERWRITE ALL SELECT * FROM "events" AS e0 } <>
                 ~s{WHERE ((e0."channel" = '#en')) IS NOT TRUE } <>
                 ~s{PARTITIONED BY 'DAY' CLUSTERED BY "channel"}
    end

    test "deletes from the query's prefix" do
      TestRepo.delete_all(
        from(e in "events", prefix: "druid"),
        [interval: :all, partitioned_by: :day] ++ druid()
      )

      assert %{
               "query" =>
                 "REPLACE INTO \"druid\".\"events\" OVERWRITE ALL SELECT * FROM \"druid\".\"events\" AS e0" <>
                   _
             } =
               submitted()
    end

    test "raises when the task fails" do
      assert_raise Druid.Tasks.Error, ~r/task t1 failed: boom/, fn ->
        TestRepo.delete_all(
          Event,
          [interval: :all, partitioned_by: :day] ++ druid(status: "FAILED")
        )
      end
    end

    test "needs :interval and :partitioned_by, and sends nothing without them" do
      assert_raise ArgumentError, ~r/needs an :interval/, fn ->
        TestRepo.delete_all(Event, [partitioned_by: :day] ++ druid())
      end

      assert_raise ArgumentError, ~r/needs an :interval/, fn ->
        TestRepo.delete_all(Event, [interval: nil, partitioned_by: :day] ++ druid())
      end

      assert_raise ArgumentError, ~r/:partitioned_by option to delete/, fn ->
        TestRepo.delete_all(Event, [interval: :all] ++ druid())
      end

      assert_raise ArgumentError, ~r/:interval needs an interval with date/, fn ->
        TestRepo.delete_all(
          Event,
          [interval: Ecto.Druid.Interval.last(day: 1), partitioned_by: :day] ++ druid()
        )
      end

      refute_received {:request, _, _, _}
    end

    test "only takes a data source and where clauses" do
      opts = [interval: :all, partitioned_by: :day] ++ druid()

      assert_raise Ecto.QueryError, ~r/only takes a data source and where clauses/, fn ->
        TestRepo.delete_all(from(e in Event, join: w in "wikipedia", on: true), opts)
      end

      assert_raise Ecto.QueryError, ~r/only takes a data source and where clauses/, fn ->
        TestRepo.delete_all(from(e in Event, select: e.channel), opts)
      end

      assert_raise Ecto.QueryError, ~r/not a subquery or fragment/, fn ->
        TestRepo.delete_all(from(e in fragment("TABLE(APPEND('a', 'b'))")), opts)
      end

      refute_received {:request, _, _, _}
    end
  end
end
