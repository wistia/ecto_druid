defmodule Ecto.Adapters.Druid.ToNativeTest do
  use ExUnit.Case
  import Ecto.Query
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  # The native query EXPLAIN PLAN FOR returns for
  #   SELECT w0."page", sum(w0."added") ... GROUP BY w0."page"
  @planned %{
    "queryType" => "groupBy",
    "dataSource" => %{"type" => "table", "name" => "wikipedia"},
    "granularity" => %{"type" => "all"},
    "dimensions" => [%{"type" => "default", "dimension" => "page", "outputName" => "d0"}],
    "aggregations" => [%{"type" => "longSum", "name" => "a0", "fieldName" => "added"}],
    "context" => %{"sqlQueryId" => "planned", "skipEmptyBuckets" => false}
  }

  @plan %{
    "query" => @planned,
    "signature" => [%{"name" => "d0", "type" => "STRING"}, %{"name" => "a0", "type" => "LONG"}],
    "columnMappings" => [
      %{"queryColumn" => "d0", "outputColumn" => "page"},
      %{"queryColumn" => "a0", "outputColumn" => "EXPR$1"}
    ]
  }

  # Answers the EXPLAIN with `plan` and sends each request body to the test
  # process.
  defp druid(plan) do
    test = self()

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {conn.request_path, Jason.decode!(body)})

      response = [[Jason.encode!(plan), "[]", "{}"]]

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(response))
    end
  end

  defp query do
    from(w in Wikipedia, where: w.page == ^"a", group_by: w.page, select: {w.page, sum(w.added)})
  end

  describe "to_native/2" do
    test "returns the planned native query without its SQL query id" do
      native = TestRepo.to_native(query(), plug: druid([@plan]))

      assert native == put_in(@planned, ["context"], %{"skipEmptyBuckets" => false})
    end

    test "plans the SQL with its params and context" do
      TestRepo.to_native(query(), plug: druid([@plan]), context: %{sqlTimeZone: "UTC"})

      assert_received {"/druid/v2/sql", explain}
      assert "EXPLAIN PLAN FOR SELECT " <> _ = explain["query"]
      assert explain["parameters"] == [%{"type" => "VARCHAR", "value" => "a"}]
      assert explain["context"]["sqlTimeZone"] == "UTC"
    end

    test "raises when Druid plans more than one native query" do
      assert_raise ArgumentError, ~r/one native query/, fn ->
        TestRepo.to_native(query(), plug: druid([@plan, @plan]))
      end
    end
  end
end
