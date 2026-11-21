defmodule Ecto.Druid.TestTest do
  # StubRepo is configured with `plug: {Req.Test, StubRepo}`, the way an app's
  # test repo would be, and each test stubs it in its own process
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Adapters.Druid.StubRepo
  alias Ecto.Druid.Test.Request

  defmodule Edit do
    use Ecto.Schema

    @primary_key false
    schema "edits" do
      field :time, :utc_datetime_usec, source: :__time
      field :day, :date
      field :local, :naive_datetime
      field :druid_time, Ecto.Druid.DateTime
      field :channel, :string
      field :added, :integer
      field :ratio, :decimal
      field :robot, :boolean
      field :tags, {:array, :string}
      field :users, Ecto.Druid.ThetaSketch
      field :estimate, Ecto.Druid.Estimate
      field :histogram, Ecto.Druid.DSHistogram
      field :attributes, Ecto.Druid.JSON
    end
  end

  defmodule Event do
    use Ecto.Schema

    @primary_key false
    schema "events" do
      field :time, :utc_datetime, source: :__time
      field :channel, :string
    end
  end

  # Stubs the repo with `fun`, and sends each request to the test
  defp stub(fun) do
    test = self()

    Ecto.Druid.Test.stub(StubRepo, fn request ->
      send(test, {:druid, request})
      fun.(request)
    end)
  end

  describe "SQL queries" do
    test "returns the stub's rows and passes it the query" do
      stub(fn %Request{type: :sql} -> [["#en", 3], ["#fr", 1]] end)

      query =
        from e in "edits",
          where: e.added > ^1 and e.channel != ^"#de",
          group_by: e.channel,
          select: {e.channel, count()}

      assert StubRepo.all(query, context: %{sqlTimeZone: "Etc/UTC"}) == [{"#en", 3}, {"#fr", 1}]

      assert_received {:druid, %Request{query: sql, params: [1, "#de"], context: context}}
      assert sql =~ ~s(FROM "edits")
      assert %{"sqlQueryId" => _, "sqlTimeZone" => "Etc/UTC"} = context
    end

    test "sends values the way Druid does, so they load like Druid's" do
      stub(fn _ ->
        [
          [
            ~U[2026-01-02 03:04:05.123456Z],
            ~D[2026-01-02],
            ~N[2026-01-02 03:04:05],
            ~U[2026-01-02 03:04:05Z],
            "#en",
            3,
            Decimal.new("1.5"),
            true,
            ["a", "b"],
            "AQEDAA==",
            %Ecto.Druid.Estimate{value: 10.0, lower_bound: 9.0, upper_bound: 11.0},
            [0.0, 1.5],
            # A VARCHAR column holding JSON, as Druid sends it
            ~s({"page":"Main"})
          ]
        ]
      end)

      assert [edit] = StubRepo.all(Edit)

      expected = %Edit{
        time: ~U[2026-01-02 03:04:05.123000Z],
        day: ~D[2026-01-02],
        local: ~N[2026-01-02 03:04:05],
        druid_time: ~U[2026-01-02 03:04:05.000Z],
        channel: "#en",
        added: 3,
        ratio: Decimal.new("1.5"),
        robot: true,
        tags: ["a", "b"],
        users: "AQEDAA==",
        estimate: %Ecto.Druid.Estimate{value: 10.0, lower_bound: 9.0, upper_bound: 11.0},
        histogram: [0.0, 1.5],
        attributes: %{"page" => "Main"}
      }

      assert %{edit | __meta__: expected.__meta__} == expected
    end

    test "a timestamp selected without a type comes back as Druid's string" do
      stub(fn _ -> [[~U[2026-01-02 03:04:05Z]]] end)

      assert StubRepo.all(from e in "edits", select: e.__time) == ["2026-01-02T03:04:05.000Z"]
    end

    test "works for one/2 and no rows" do
      stub(fn _ -> [] end)

      assert StubRepo.all(Edit) == []
      assert StubRepo.one(from e in Edit, select: e.channel) == nil
    end

    test "streams rows" do
      stub(fn _ -> [["#en"], ["#fr"], ["#de"]] end)

      query = from e in Edit, select: e.channel
      assert query |> StubRepo.stream() |> Enum.to_list() == ["#en", "#fr", "#de"]

      stub(fn _ -> [] end)
      assert query |> StubRepo.stream() |> Enum.to_list() == []
    end

    test "returns Druid's error response" do
      stub(fn _ -> {:error, :invalid_input, "Column 'nope' not found in any table"} end)

      error = assert_raise Druid.Client.RequestError, fn -> StubRepo.all(Edit) end
      assert error.status == 400
      assert error.error_code == "invalidInput"
      assert error.category == "INVALID_INPUT"
      assert error.error_message == "Column 'nope' not found in any table"

      stub(fn _ -> {:error, :capacity_exceeded, "Too many queries"} end)

      assert %{status: 429, category: "CAPACITY_EXCEEDED"} =
               assert_raise(Druid.Client.RequestError, fn -> StubRepo.all(Edit, retry: false) end)
    end

    test "times out and cancels the query" do
      stub(fn _ -> :timeout end)

      assert_raise Req.TransportError, ~r/timeout/, fn -> StubRepo.all(Edit) end
      assert_received {:druid, %Request{type: :sql}}
      refute_received {:druid, _}
    end

    test "answers queries from processes the test starts" do
      stub(fn _ -> [["#en"]] end)

      task = Task.async(fn -> StubRepo.all(from e in Edit, select: e.channel) end)
      assert Task.await(task) == ["#en"]
    end

    test "raises when the stub doesn't return rows" do
      stub(fn _ -> [%{"channel" => "#en"}] end)

      assert_raise ArgumentError, ~r/list of values in the order the query selects them/, fn ->
        StubRepo.all(Edit)
      end

      stub(fn _ -> {:failed, "boom"} end)
      assert_raise ArgumentError, ~r/for a :sql request/, fn -> StubRepo.all(Edit) end
    end
  end

  describe "queries from deep storage" do
    test "returns the stub's rows" do
      stub(fn %Request{type: :statement} -> [["#en", 3], ["#fr", 1]] end)

      query = from e in Edit, group_by: e.channel, select: {e.channel, count()}
      assert StubRepo.all(query, deep_storage: true) == [{"#en", 3}, {"#fr", 1}]

      assert_received {:druid, %Request{type: :statement, query: "SELECT " <> _}}

      assert query |> StubRepo.stream(deep_storage: true) |> Enum.to_list() ==
               [{"#en", 3}, {"#fr", 1}]

      stub(fn %Request{type: :statement} -> [] end)
      assert StubRepo.all(query, deep_storage: true) == []
      assert query |> StubRepo.stream(deep_storage: true) |> Enum.to_list() == []
    end

    test "fails the statement" do
      stub(fn _ -> {:failed, "Out of memory"} end)

      error =
        assert_raise Ecto.Adapters.Druid.StatementError, fn ->
          StubRepo.all(Edit, deep_storage: true)
        end

      assert error.state == "FAILED"
      assert error.details["errorMessage"] == "Out of memory"

      stub(fn _ -> {:error, :invalid_input, "bad"} end)

      assert %{error_code: "invalidInput"} =
               assert_raise(Druid.Client.RequestError, fn ->
                 StubRepo.all(Edit, deep_storage: true)
               end)
    end
  end

  describe "SQL-based ingestion" do
    @rows [
      %{time: ~U[2026-01-01 00:00:00Z], channel: "#en"},
      %{time: ~U[2026-01-01 01:00:00Z], channel: "#fr"}
    ]

    test "insert_all succeeds and waits for segments" do
      stub(fn %Request{type: :ingest} -> :ok end)

      assert {2, nil} =
               StubRepo.insert_all(Event, @rows, partitioned_by: :day, wait_for_segments: true)

      assert_received {:druid,
                       %Request{type: :ingest, query: ~s(INSERT INTO "events") <> _} = request}

      assert "2026-01-01T00:00:00Z" in request.params
      refute_received {:druid, _}
    end

    test "insert_all returns the rows Druid reports writing" do
      stub(fn _ -> {:ok, 7} end)

      query = from e in "events", select: %{__time: e.__time, channel: e.channel}
      assert {7, nil} = StubRepo.insert_all("event_copies", query, partitioned_by: :day)
    end

    test "delete_all and update_all succeed" do
      stub(fn %Request{type: :ingest, query: "REPLACE INTO " <> _} -> :ok end)

      assert {0, nil} =
               StubRepo.delete_all(from(e in Event, where: e.channel == "#en"),
                 interval: :all,
                 partitioned_by: :day
               )
    end

    test "fails the task" do
      stub(fn _ -> {:failed, "Too many rows"} end)

      error =
        assert_raise Druid.Tasks.Error, fn ->
          StubRepo.insert_all(Event, @rows, partitioned_by: :day, wait_for_segments: true)
        end

      assert error.reason == :failed
      assert error.message =~ "Too many rows"
      assert error.status["dataSource"] == "events"
    end
  end

  describe "native queries" do
    test "turns flat rows into Druid's response for each query type" do
      timeseries = %{
        queryType: "timeseries",
        dataSource: "edits",
        granularity: "day",
        intervals: ["2026-01-01/2026-01-03"],
        aggregations: [%{type: "count", name: "edits"}]
      }

      rows = [
        %{"__time" => "2026-01-01T00:00:00.000Z", "edits" => 3},
        %{"__time" => "2026-01-02T00:00:00.000Z", "edits" => 1}
      ]

      stub(fn %Request{type: :native} -> rows end)
      assert StubRepo.native_query!(timeseries) == rows

      assert_received {:druid,
                       %Request{query: %{"queryType" => "timeseries"}, context: %{"queryId" => _}}}

      assert StubRepo.native_query!(timeseries, raw: true) == [
               %{"timestamp" => "2026-01-01T00:00:00.000Z", "result" => %{"edits" => 3}},
               %{"timestamp" => "2026-01-02T00:00:00.000Z", "result" => %{"edits" => 1}}
             ]

      top_n =
        timeseries
        |> Map.merge(%{queryType: "topN", dimension: "channel", metric: "edits", threshold: 2})

      rows = [
        %{"__time" => "2026-01-01T00:00:00.000Z", "channel" => "#en", "edits" => 3},
        %{"__time" => "2026-01-01T00:00:00.000Z", "channel" => "#fr", "edits" => 2},
        %{"__time" => "2026-01-02T00:00:00.000Z", "channel" => "#en", "edits" => 1}
      ]

      stub(fn _ -> rows end)
      assert StubRepo.native_query!(top_n) == rows

      assert [%{"result" => [_, _]}, %{"result" => [_]}] =
               StubRepo.native_query!(top_n, raw: true)

      group_by =
        timeseries
        |> Map.merge(%{queryType: "groupBy", granularity: "all", dimensions: ["channel"]})

      # Atom keys work too
      stub(fn _ -> [%{channel: "#en", edits: 3}, %{channel: "#fr", edits: 2}] end)
      expected = [%{"channel" => "#en", "edits" => 3}, %{"channel" => "#fr", "edits" => 2}]
      assert StubRepo.native_query!(group_by) == expected

      assert [%{"version" => "v1", "timestamp" => "2026-01-01", "event" => _} | _] =
               StubRepo.native_query!(group_by, raw: true)

      as_array = Map.put(group_by, :context, %{resultAsArray: true})
      assert StubRepo.native_query!(as_array) == expected
      assert StubRepo.native_query!(as_array, raw: true) == [["#en", 3], ["#fr", 2]]

      scan = %{
        queryType: "scan",
        dataSource: "edits",
        intervals: ["2026-01-01/2026-01-03"],
        columns: ["__time", "channel"]
      }

      rows = [%{"__time" => 1_767_225_600_000, "channel" => "#en"}]
      stub(fn _ -> rows end)
      assert StubRepo.native_query!(scan) == rows

      compacted = Map.put(scan, :resultFormat, "compactedList")
      assert StubRepo.native_query!(compacted) == rows

      assert [%{"columns" => ["__time", "channel"], "events" => [[1_767_225_600_000, "#en"]]}] =
               StubRepo.native_query!(compacted, raw: true)

      stub(fn _ -> [] end)
      assert StubRepo.native_query!(scan) == []
    end

    test "sends other responses as they are" do
      metadata = [%{"id" => "merged", "columns" => %{"channel" => %{"type" => "STRING"}}}]
      stub(fn %Request{query: %{"queryType" => "segmentMetadata"}} -> metadata end)

      query = %{queryType: "segmentMetadata", dataSource: "edits"}
      assert StubRepo.native_query!(query) == metadata

      raw = [%{"timestamp" => "2026-01-01T00:00:00.000Z", "result" => %{"edits" => 3}}]
      stub(fn _ -> {:raw, raw} end)

      timeseries = %{queryType: "timeseries", dataSource: "edits", granularity: "all"}
      assert StubRepo.native_query!(timeseries, raw: true) == raw
    end

    test "returns errors and cancels on timeout" do
      query = %{queryType: "timeseries", dataSource: "edits", granularity: "all"}

      stub(fn _ -> {:error, :not_found, "Datasource edits not found"} end)

      assert {:error, %Ecto.Adapters.Druid.NativeQueryError{reason: reason}} =
               StubRepo.native_query(query)

      assert %Druid.Client.RequestError{status: 404, error_code: "notFound"} = reason

      stub(fn _ -> :timeout end)

      assert {:error, %Ecto.Adapters.Druid.NativeQueryError{canceled: true}} =
               StubRepo.native_query(query)
    end

    test "a query the stub has no clause for is the error's reason" do
      stub(fn %Request{type: :sql} -> [] end)

      assert {:error, %Ecto.Adapters.Druid.NativeQueryError{reason: %FunctionClauseError{}}} =
               StubRepo.native_query(%{queryType: "timeseries", dataSource: "edits"})
    end
  end

  test "raises on requests it doesn't stub" do
    stub(fn _ -> flunk("not called") end)

    assert_raise ArgumentError, ~r/doesn't stub GET \/druid\/indexer\/v1\/supervisor/, fn ->
      Druid.Client.Supervisor.list()
      |> Druid.Client.request!(host: "druid.example.com", port: 8888, plug: {Req.Test, StubRepo})
    end
  end

  test "raises on an unknown error category" do
    stub(fn _ -> {:error, :oops, "bad"} end)

    assert_raise ArgumentError, ~r/unknown Druid error category :oops/, fn ->
      StubRepo.all(Edit)
    end
  end
end
