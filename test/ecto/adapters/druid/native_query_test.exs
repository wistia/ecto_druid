defmodule Ecto.Adapters.Druid.NativeQueryTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.{NativeQueryError, TestRepo, Wikipedia}

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  # Answers every request with `response` and sends each request body to the
  # test process.
  defp druid(response) do
    test = self()

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {conn.request_path, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end
  end

  @topn %{
    queryType: "topN",
    dataSource: "wikipedia",
    dimension: "page",
    aggregations: [%{type: "count", name: "rows"}]
  }

  @topn_results [
    %{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => [%{"page" => "a", "rows" => 2}]}
  ]

  describe "native_query/2" do
    test "flattens results into rows by default" do
      assert TestRepo.native_query(@topn, plug: druid(@topn_results)) ==
               {:ok, [%{"__time" => "2016-06-27T00:00:00.000Z", "page" => "a", "rows" => 2}]}

      assert_received {"/druid/v2/", body}
      assert body["queryType"] == "topN"
    end

    test "returns Druid's response as is with raw: true" do
      assert TestRepo.native_query(@topn, plug: druid(@topn_results), raw: true) ==
               {:ok, @topn_results}
    end

    test "names array results with :columns" do
      query = %{queryType: "windowOperator", dataSource: "wikipedia"}

      assert TestRepo.native_query(query, plug: druid([["a", 1]]), columns: ["page", "rank"]) ==
               {:ok, [%{"page" => "a", "rank" => 1}]}
    end

    test "returns results of query types it doesn't flatten as is" do
      results = [%{"timestamp" => "2016-06-27T00:00:00.000Z", "result" => %{"minTime" => "x"}}]
      query = %{queryType: "timeBoundary", dataSource: "wikipedia"}

      assert TestRepo.native_query(query, plug: druid(results)) == {:ok, results}
    end

    test "gives every query a queryId unless it has one" do
      TestRepo.native_query(@topn, plug: druid(@topn_results))
      assert_received {_, %{"context" => %{"queryId" => query_id}}}
      assert {:ok, _} = Ecto.UUID.cast(query_id)

      query = Map.put(@topn, :context, %{queryId: "mine", timeout: 1000})
      TestRepo.native_query(query, plug: druid(@topn_results))
      assert_received {_, %{"context" => %{"queryId" => "mine", "timeout" => 1000}}}
    end

    test "returns an error with the queryId when Druid responds with one" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 400, ~s({"error":"bad"})) end
      query = Map.put(@topn, :context, %{queryId: "q1"})

      assert {:error, %NativeQueryError{query_id: "q1", canceled: false} = error} =
               TestRepo.native_query(query, plug: plug)

      assert %Druid.Client.RequestError{status: 400} = error.reason
      assert Exception.message(error) =~ "native query q1 failed"
    end

    test "cancels the query when the request times out" do
      test = self()

      adapter = fn request ->
        send(test, {request.method, request.url.path})

        case request.method do
          :post -> {request, %Req.TransportError{reason: :timeout}}
          :delete -> {request, Req.Response.new(status: 202)}
        end
      end

      query = Map.put(@topn, :context, %{queryId: "slow"})

      assert {:error, %NativeQueryError{query_id: "slow", canceled: true} = error} =
               TestRepo.native_query(query, adapter: adapter)

      assert %Req.TransportError{reason: :timeout} = error.reason
      assert_received {:post, "/druid/v2/"}
      assert_received {:delete, "/druid/v2/slow"}
    end

    test "merges the repo's context with merge_context: true" do
      config = Application.get_env(:ecto_druid, TestRepo)
      on_exit(fn -> Application.put_env(:ecto_druid, TestRepo, config) end)

      Application.put_env(
        :ecto_druid,
        TestRepo,
        Keyword.put(config, :context, %{timeout: 1000, priority: 1})
      )

      query = Map.put(@topn, :context, %{priority: 5})

      TestRepo.native_query(query, plug: druid(@topn_results))
      assert_received {_, %{"context" => context}}
      refute Map.has_key?(context, "timeout")

      TestRepo.native_query(query, plug: druid(@topn_results), merge_context: true)
      assert_received {_, %{"context" => %{"timeout" => 1000, "priority" => 5}}}
    end

    test "takes a schema as the dataSource" do
      query = %{@topn | dataSource: Wikipedia, dimension: "page"}
      TestRepo.native_query(query, plug: druid(@topn_results), check_columns: true)
      assert_received {_, %{"dataSource" => "wikipedia"}}

      query = %{@topn | dataSource: %{type: "table", name: Wikipedia}}
      TestRepo.native_query(query, plug: druid(@topn_results))
      assert_received {_, %{"dataSource" => %{"type" => "table", "name" => "wikipedia"}}}
    end

    test "checks the columns a query reads against its schema with check_columns: true" do
      query = %{
        queryType: "groupBy",
        dataSource: Wikipedia,
        granularity: "all",
        virtualColumns: [%{type: "expression", name: "net", expression: "added - deleted"}],
        dimensions: ["page", %{type: "default", dimension: "user", outputName: "u"}],
        filter: %{type: "equals", column: "__time", matchValueType: "LONG", matchValue: 0},
        aggregations: [
          %{type: "longSum", name: "net", fieldName: "net"},
          %{type: "longSum", name: "added", fieldName: "added"}
        ],
        postAggregations: [%{type: "fieldAccess", name: "a", fieldName: "added"}]
      }

      assert {:ok, _} = TestRepo.native_query(query, plug: druid([]), check_columns: true)
      assert_received {"/druid/v2/", _}

      query = %{query | dimensions: ["page", "nope", %{type: "default", dimension: "missing"}]}

      assert_raise ArgumentError, ~r/doesn't define: \["missing", "nope"\]/, fn ->
        TestRepo.native_query(query, plug: druid([]), check_columns: true)
      end

      refute_received {_, _}
    end

    test "check_columns needs a schema dataSource" do
      assert_raise ArgumentError, ~r/needs the query's dataSource to be a schema/, fn ->
        TestRepo.native_query(@topn, plug: druid([]), check_columns: true)
      end
    end
  end

  describe "native_query!/2" do
    test "returns the results" do
      assert [%{"page" => "a"}] = TestRepo.native_query!(@topn, plug: druid(@topn_results))
    end

    test "raises the error" do
      plug = fn conn -> Plug.Conn.send_resp(conn, 500, "oops") end

      assert_raise NativeQueryError, fn -> TestRepo.native_query!(@topn, plug: plug) end
    end
  end
end
