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

  defmodule DruidEvent do
    use Ecto.Druid.Schema
    @primary_key false
    schema "events" do
      timestamp :time
      dimension :channel, :string
      dimension :count, :integer
      dimension :tags, {:array, :string}, multi_value: true
      dimension :labels, {:array, :string}
      dimension :attrs, :map
      metric :added, :integer, aggregate: :sum
      metric :users, Ecto.Druid.ThetaSketch
      field :note, :string
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

  # Answers the submit, status and report requests of a successful task and
  # records what was asked.
  defp druid(opts \\ []) do
    test = self()
    status = Keyword.get(opts, :status, "SUCCESS")
    report = Keyword.get(opts, :report, @report)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = if body == "", do: nil, else: Jason.decode!(body)
      send(test, {:request, conn.method, conn.request_path, body})

      {code, response} =
        case conn.request_path do
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

    test "sends an Ecto.Druid.Schema timestamp as a TIMESTAMP" do
      TestRepo.insert_all(
        DruidEvent,
        [%{time: ~U[2026-01-01 00:00:00Z], channel: "#en"}],
        [partitioned_by: :day] ++ druid()
      )

      %{"query" => sql, "parameters" => params} = submitted()

      assert [%{"__time" => %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00Z"}}] =
               sent_rows(sql, params)
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
  end

  describe "delete_all/2" do
    test "rewrites the interval without the matching rows" do
      query = from e in Event, where: e.channel == ^"#en"

      # The task doesn't report how many rows it dropped, so the count is 0
      assert {0, nil} =
               TestRepo.delete_all(
                 query,
                 [interval: "2026-01-01/2026-01-02", partitioned_by: :day] ++ druid()
               )

      start = %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00"}
      stop = %{"type" => "TIMESTAMP", "value" => "2026-01-02T00:00:00"}
      channel = %{"type" => "VARCHAR", "value" => "#en"}

      %{"query" => sql, "parameters" => params} = submitted()

      # IS NOT TRUE keeps the rows the condition is NULL for
      assert sql ==
               ~s{REPLACE INTO "events" OVERWRITE WHERE "__time" >= ? AND "__time" < ? } <>
                 ~s{SELECT * FROM "events" AS e0 } <>
                 ~s{WHERE e0."__time" >= ? AND e0."__time" < ? AND ((e0."channel" = ?)) IS NOT TRUE } <>
                 ~s{PARTITIONED BY 'DAY'}

      assert params == [start, stop, start, stop, channel]

      # Nothing else is sent: the task is the only statement
      refute_received {:request, "POST", "/druid/v2/sql", _}
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
      assert {0, nil} =
               TestRepo.delete_all(
                 Event,
                 [interval: {~D[2026-01-01], ~D[2026-01-02]}, partitioned_by: :day] ++ druid()
               )

      assert %{"query" => sql, "parameters" => [_, _, _, _]} = submitted()
      assert sql =~ ~s{AS e0 WHERE e0."__time" >= ? AND e0."__time" < ? AND FALSE PARTITIONED BY}
    end

    test "rewrites every time chunk with interval: :all" do
      query = from e in Event, where: e.channel == "#en"

      TestRepo.delete_all(
        query,
        [interval: :all, partitioned_by: :day, clustered_by: [:channel]] ++ druid()
      )

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

  describe "update_all/3" do
    @bounds [
      %{"type" => "TIMESTAMP", "value" => "2026-01-01T00:00:00"},
      %{"type" => "TIMESTAMP", "value" => "2026-01-02T00:00:00"}
    ]

    defp update_opts(opts \\ []) do
      [interval: "2026-01-01/2026-01-02", partitioned_by: :day] ++ opts ++ druid()
    end

    test "rewrites the interval with every column, changing the matched rows" do
      query =
        from e in DruidEvent, where: e.channel == ^"#en", update: [set: [channel: ^"#fr"]]

      assert {0, nil} = TestRepo.update_all(query, [], update_opts())

      %{"query" => sql, "parameters" => params} = submitted()

      assert sql ==
               ~s{REPLACE INTO "events" OVERWRITE WHERE "__time" >= ? AND "__time" < ? } <>
                 ~s{SELECT e0."__time", } <>
                 ~s{CASE WHEN e0."__match" THEN CAST(? AS VARCHAR) ELSE e0."channel" END AS "channel", } <>
                 ~s{e0."count", e0."tags", e0."labels", e0."attrs", e0."added", e0."users" } <>
                 ~s{FROM (SELECT *, ((e0."channel" = ?)) IS TRUE AS "__match" FROM "events" AS e0 } <>
                 ~s{WHERE e0."__time" >= ? AND e0."__time" < ?) AS e0 } <>
                 ~s{PARTITIONED BY 'DAY'}

      assert params ==
               @bounds ++
                 [
                   %{"type" => "VARCHAR", "value" => "#fr"},
                   %{"type" => "VARCHAR", "value" => "#en"}
                 ] ++ @bounds
    end

    test "sends each update's parameters where the SQL takes them" do
      query =
        from e in DruidEvent,
          where: e.channel == ^"#en",
          update: [
            set: [channel: ^"#fr"],
            inc: [count: ^2],
            push: [labels: ^"new"],
            pull: [tags: ^"old"]
          ]

      TestRepo.update_all(query, [], update_opts())

      %{"query" => sql, "parameters" => params} = submitted()

      assert sql =~
               ~s{THEN CAST(e0."count" + ? AS BIGINT) ELSE e0."count" END AS "count", }

      # A multi-value column is changed as an array, then made multi-value again
      assert sql =~
               ~s{ARRAY_TO_MV(CASE WHEN e0."__match" THEN MV_TO_ARRAY(MV_FILTER_NONE(e0."tags", ARRAY[?])) } <>
                 ~s{ELSE MV_TO_ARRAY(e0."tags") END) AS "tags", }

      assert sql =~
               ~s{THEN CASE WHEN ARRAY_SLICE(e0."labels", 0) IS NULL THEN ARRAY[?] } <>
                 ~s{ELSE ARRAY_APPEND(ARRAY_SLICE(e0."labels", 0), ?) END } <>
                 ~s{ELSE ARRAY_SLICE(e0."labels", 0) END AS "labels", }

      # Columns are in schema order, and push takes its value twice
      assert Enum.map(params, & &1["value"]) ==
               Enum.map(@bounds, & &1["value"]) ++
                 ["#fr", 2, "old", "new", "new", "#en"] ++ Enum.map(@bounds, & &1["value"])
    end

    test "takes runtime updates, pushing onto a multi-value column" do
      TestRepo.update_all(DruidEvent, [push: [tags: "new"]], update_opts())

      assert %{"query" => sql, "parameters" => params} = submitted()

      assert sql =~
               ~s{ARRAY_TO_MV(CASE WHEN MV_TO_ARRAY(e0."tags") IS NULL THEN ARRAY[?] } <>
                 ~s{ELSE ARRAY_APPEND(MV_TO_ARRAY(e0."tags"), ?) END) AS "tags"}

      assert Enum.map(params, & &1["value"]) ==
               ["2026-01-01T00:00:00", "2026-01-02T00:00:00", "new", "new"] ++
                 ["2026-01-01T00:00:00", "2026-01-02T00:00:00"]
    end

    test "sets a multi-value column from a list" do
      query = from e in DruidEvent, where: e.channel == "#en"
      TestRepo.update_all(query, [set: [tags: ["a", "b"]]], update_opts())

      assert %{"query" => sql, "parameters" => [_, _, tags, _, _]} = submitted()
      assert tags == %{"type" => "ARRAY", "value" => ["a", "b"]}

      assert sql =~
               ~s{ARRAY_TO_MV(CASE WHEN e0."__match" THEN ? ELSE MV_TO_ARRAY(e0."tags") END) AS "tags"}
    end

    test "changes every row in the interval without a where clause" do
      query = from(d in DruidEvent, update: [set: [channel: fragment("UPPER(?)", d.channel)]])

      TestRepo.update_all(
        query,
        [],
        [interval: :all, partitioned_by: :day, clustered_by: [:channel]] ++ druid()
      )

      assert %{"query" => sql, "parameters" => []} = submitted()

      assert sql ==
               ~s{REPLACE INTO "events" OVERWRITE ALL } <>
                 ~s{SELECT e0."__time", CAST(UPPER(e0."channel") AS VARCHAR) AS "channel", } <>
                 ~s{e0."count", e0."tags", e0."labels", e0."attrs", e0."added", e0."users" } <>
                 ~s{FROM (SELECT * FROM "events" AS e0) AS e0 } <>
                 ~s{PARTITIONED BY 'DAY' CLUSTERED BY "channel"}
    end

    test "raises when the task fails" do
      assert_raise Druid.Tasks.Error, ~r/task t1 failed: boom/, fn ->
        TestRepo.update_all(
          DruidEvent,
          [set: [channel: "#fr"]],
          [interval: :all, partitioned_by: :day] ++ druid(status: "FAILED")
        )
      end
    end

    test "needs an Ecto.Druid.Schema to know every column" do
      assert_raise Ecto.QueryError, ~r/needs a schema that uses Ecto.Druid.Schema/, fn ->
        TestRepo.update_all(Event, [set: [channel: "#fr"]], update_opts())
      end

      assert_raise Ecto.QueryError, ~r/needs a schema that uses Ecto.Druid.Schema/, fn ->
        TestRepo.update_all("events", [set: [channel: "#fr"]], update_opts())
      end

      refute_received {:request, _, _, _}
    end

    test "rejects changes it can't make, sending nothing" do
      for {updates, message} <- [
            {[set: [time: ~U[2026-01-01 00:00:00Z]]], ~r/can't change __time/},
            {[set: [note: "x"]], ~r/can't change note: it isn't a Druid column/},
            {[pull: [labels: "x"]], ~r/can't pull from labels: Druid has no function/},
            {[inc: [labels: ["x"]]], ~r/can't inc labels, an array column/}
          ] do
        assert_raise Ecto.QueryError, message, fn ->
          TestRepo.update_all(DruidEvent, updates, update_opts())
        end
      end

      refute_received {:request, _, _, _}
    end

    test "needs :interval and :partitioned_by, and only where clauses" do
      assert_raise ArgumentError, ~r/update_all needs an :interval/, fn ->
        TestRepo.update_all(DruidEvent, [set: [channel: "x"]], [partitioned_by: :day] ++ druid())
      end

      assert_raise ArgumentError, ~r/:partitioned_by option to update/, fn ->
        TestRepo.update_all(DruidEvent, [set: [channel: "x"]], [interval: :all] ++ druid())
      end

      assert_raise Ecto.QueryError, ~r/only takes a data source and where clauses/, fn ->
        TestRepo.update_all(
          from(d in DruidEvent, join: w in "wikipedia", on: true),
          [set: [channel: "x"]],
          update_opts()
        )
      end

      refute_received {:request, _, _, _}
    end
  end
end
