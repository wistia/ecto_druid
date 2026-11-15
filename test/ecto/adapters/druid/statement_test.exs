defmodule Ecto.Adapters.Druid.StatementTest do
  use ExUnit.Case, async: true
  alias Ecto.Adapters.Druid.Statement
  alias Ecto.Adapters.Druid.StatementError

  @path "/druid/v2/sql/statements"
  @fast [poll_interval: 1]

  # Answers each request with the next scripted response and records what
  # was asked, so tests can check the order of calls to Druid.
  defp script(responses) do
    {:ok, agent} = Agent.start_link(fn -> {responses, []} end)

    plug = fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      conn = Plug.Conn.fetch_query_params(conn)
      request = {conn.method, conn.request_path, conn.query_params, decode(body)}

      {status, response} =
        Agent.get_and_update(agent, fn
          {[next | rest], seen} -> {next, {rest, [request | seen]}}
          {[], seen} -> {{500, %{"error" => "unexpected request"}}, {[], [request | seen]}}
        end)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(response))
    end

    requests = fn -> agent |> Agent.get(&elem(&1, 1)) |> Enum.reverse() end
    {[plug: plug, host: "localhost", port: 8888, context: %{sqlQueryId: "q1"}], requests}
  end

  defp decode(""), do: nil
  defp decode(body), do: Jason.decode!(body)

  defp status(state, extra \\ %{}),
    do: {200, Map.merge(%{"queryId" => "q1", "state" => state}, extra)}

  defp success(pages) do
    status("SUCCESS", %{
      "result" => %{"pages" => Enum.map(pages, &%{"id" => &1, "numRows" => 1})}
    })
  end

  describe "options/1" do
    test "is nil unless deep storage is enabled" do
      assert Statement.options([]) == nil
      assert Statement.options(deep_storage: false) == nil
      assert Statement.options(deep_storage: true) == []
      assert Statement.options(deep_storage: [timeout: 10]) == [timeout: 10]
    end

    test "rejects other values" do
      assert_raise ArgumentError, ~r/:deep_storage/, fn -> Statement.options(deep_storage: 1) end
    end
  end

  describe "all/4" do
    test "submits, polls until success, then fetches every row" do
      {opts, requests} =
        script([
          status("ACCEPTED"),
          status("RUNNING"),
          success([0]),
          {200, [["a", 4], ["b", 2]]}
        ])

      assert Statement.all("SELECT 1", [%{type: "BIGINT", value: 1}], @fast, opts) ==
               [["a", 4], ["b", 2]]

      assert [
               {"POST", @path, %{}, submitted},
               {"GET", @path <> "/q1", %{}, nil},
               {"GET", @path <> "/q1", %{}, nil},
               {"GET", @path <> "/q1/results", %{"resultFormat" => "array"}, nil}
             ] = requests.()

      assert submitted["query"] == "SELECT 1"
      assert submitted["parameters"] == [%{"type" => "BIGINT", "value" => 1}]
      assert submitted["context"]["executionMode"] == "ASYNC"
      assert submitted["context"]["sqlQueryId"] == "q1"
    end

    test "returns no rows for an empty result" do
      {opts, _} = script([success([0]), {200, []}])
      assert Statement.all("SELECT 1", [], @fast, opts) == []
    end

    test "raises Druid's error when the statement fails" do
      details = %{"errorCode" => "Canceled", "errorMessage" => "Query canceled"}
      {opts, _} = script([status("RUNNING"), status("FAILED", %{"errorDetails" => details})])

      error =
        assert_raise StatementError, fn -> Statement.all("SELECT 1", [], @fast, opts) end

      assert error.query_id == "q1"
      assert error.state == "FAILED"
      assert error.details == details
      assert Exception.message(error) == "Statement q1 failed (Canceled): Query canceled"
    end

    test "raises the submit error when Druid rejects the statement" do
      {opts, _} = script([{400, %{"errorMessage" => "bad SQL"}}])

      assert_raise Druid.Client.RequestError, ~r/bad SQL/, fn ->
        Statement.all("SELECT", [], @fast, opts)
      end
    end

    test "cancels the statement when it runs past the timeout" do
      {opts, requests} = script([status("RUNNING"), {202, %{}}])

      error =
        assert_raise StatementError, fn ->
          Statement.all("SELECT 1", [], [timeout: 0] ++ @fast, opts)
        end

      assert error.state == "RUNNING"
      assert Exception.message(error) =~ "did not finish within 0ms"
      assert [{"POST", _, _, _}, {"DELETE", @path <> "/q1", _, _}] = requests.()
    end
  end

  describe "stream/4" do
    test "does nothing until enumerated" do
      {opts, requests} = script([])
      _stream = Statement.stream("SELECT 1", [], @fast, opts)
      assert requests.() == []
    end

    test "fetches one page at a time" do
      {opts, requests} =
        script([status("RUNNING"), success([0, 1]), {200, [["a"], ["b"]]}, {200, [["c"]]}])

      stream = Statement.stream("SELECT 1", [], @fast, opts)

      assert Enum.take(stream, 1) == [{2, [["a"], ["b"]]}]
      assert length(requests.()) == 3

      {opts, requests} =
        script([success([0, 1]), {200, [["a"], ["b"]]}, {200, [["c"]]}])

      assert Enum.to_list(Statement.stream("SELECT 1", [], @fast, opts)) ==
               [{2, [["a"], ["b"]]}, {1, [["c"]]}]

      assert [
               {"POST", _, _, _},
               {"GET", @path <> "/q1/results", %{"page" => "0", "resultFormat" => "array"}, _},
               {"GET", @path <> "/q1/results", %{"page" => "1", "resultFormat" => "array"}, _}
             ] = requests.()
    end
  end
end
