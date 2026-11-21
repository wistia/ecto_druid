if Code.ensure_loaded?(Plug.Conn) do
  defmodule Ecto.Druid.Test do
    @moduledoc """
    Stubs Druid for an app's own tests, so code that queries a Druid repo can
    be tested without a cluster.

    A stub is a function that gets each query the repo sends and returns its
    rows. The stub answers the way Druid would, in the format the request
    asked for, so the repo decodes, loads and streams the rows as it does
    Druid's. It is built on `Req.Test`, so stubs are per test process and
    work in `async: true` tests.

    Needs the `:plug` package, which `Req.Test` uses: add
    `{:plug, "~> 1.15", only: :test}` to your deps if you don't have it.

    ## Setup

    Send the repo's requests to `Req.Test` in `config/test.exs`, named after
    the repo:

        config :my_app, MyApp.DruidRepo, plug: {Req.Test, MyApp.DruidRepo}

    Then stub it in a test:

        test "counts edits by channel" do
          Ecto.Druid.Test.stub(MyApp.DruidRepo, fn
            %{type: :sql, query: sql, params: ["#en.wikipedia"]} ->
              assert sql =~ ~s(GROUP BY)
              [["#en.wikipedia", 3]]
          end)

          assert MyApp.Wiki.counts("#en.wikipedia") == [{"#en.wikipedia", 3}]
        end

    A request the function has no clause for raises `FunctionClauseError` in
    the code under test, or, from `native_query/2`, is the returned
    `Ecto.Adapters.Druid.NativeQueryError`'s `:reason`. To assert that a
    query was sent, send a message from the stub:

        test = self()

        Ecto.Druid.Test.stub(MyApp.DruidRepo, fn request ->
          send(test, {:druid, request})
          []
        end)

        MyApp.Wiki.counts("#en.wikipedia")
        assert_received {:druid, %{type: :sql}}

    Tasks the test starts, and LiveViews under `Phoenix.LiveViewTest`, find
    the test's stub. Another process that queries the repo, such as a
    GenServer that was already running, needs `Req.Test.allow/3`, or
    `Req.Test.set_req_test_to_shared/1` in a test that isn't async.

    ## Requests

    The stub function gets an `Ecto.Druid.Test.Request`, whose `:type` says
    what was asked:

      * `:sql` - A query to the Broker, from `Repo.all/2`, `Repo.one/2`,
        `Repo.stream/2` or `Repo.to_native/2`, among others.
      * `:statement` - A query from deep storage (`deep_storage: true`).
      * `:ingest` - SQL-based ingestion, from `Repo.insert_all/3`,
        `Repo.delete_all/2` or `Repo.update_all/3`.
      * `:native` - A native query, from `Repo.native_query/2`.

    The requests Druid needs to finish these, such as polling a task or
    fetching a statement's results, are answered by the stub without calling
    the function. So are cancels. Any other request, such as one to the
    supervisor API, raises. Stub those with your own plug and `Req.Test`.

    ## Return values

    For `:sql` and `:statement` requests, return the rows as lists, with the
    values in the order the query selects them:

        [["#en.wikipedia", 3], ["#fr.wikipedia", 1]]

    The values are sent as JSON, the way Druid sends them, so they load as
    Druid's would: `DateTime`, `NaiveDateTime` and `Date` values are sent as
    Druid formats timestamps, `Decimal`s as numbers, and
    `Ecto.Druid.Estimate`s as Druid's arrays. Return a sketch as its Base64
    string.

    For `:native` requests, return the rows as the repo returns them, as maps
    keyed by column, with the time under `"__time"`. The stub turns them into
    the response Druid sends for the query's type, which
    `Ecto.Druid.Native.rows/3` flattens back:

        [%{"__time" => "2016-06-27T00:00:00.000Z", "edits" => 24433}]

    For query types `native_query/2` doesn't flatten, such as
    `segmentMetadata`, return Druid's response. Return `{:raw, response}` to
    send any response as is.

    For `:ingest` requests, return `:ok`, or `{:ok, rows}` for the number of
    rows Druid reports writing, which `Repo.insert_all/3` returns. Without
    it, `insert_all` returns the number of rows it was given.

    Any request can fail instead:

      * `{:error, category, message}` - Druid responds with an error, as it
        does for a query that doesn't plan. `category` is Druid's error
        category as an atom, such as `:invalid_input`, `:not_found`,
        `:capacity_exceeded` or `:timeout`, which sets the HTTP status and
        the `errorCode`.
      * `:timeout` - The request times out without a response, which raises
        a `Req.TransportError` after the repo cancels the query.
      * `{:failed, message}` - For `:statement` and `:ingest` requests, the
        statement or task is accepted, then fails, which raises
        `Ecto.Adapters.Druid.StatementError` or `Druid.Tasks.Error`.

    ## Example

        Ecto.Druid.Test.stub(MyApp.DruidRepo, fn
          %{type: :sql, query: "SELECT" <> _} ->
            [[~U[2016-06-27 00:00:00Z], 24433]]

          %{type: :native, query: %{"queryType" => "timeseries"}} ->
            [%{"__time" => "2016-06-27T00:00:00.000Z", "edits" => 24433}]

          %{type: :ingest} ->
            {:ok, 2}

          %{type: :statement} ->
            {:error, :invalid_input, "Column 'nope' not found in any table"}
        end)
    """

    alias Plug.Conn

    defmodule Request do
      @moduledoc """
      A request the repo sent to Druid, as `Ecto.Druid.Test` passes it to a
      stub.

        * `:type` - `:sql`, `:statement`, `:ingest` or `:native`. See
          "Requests" in `Ecto.Druid.Test`.
        * `:query` - The SQL, or the native query as Druid received it, with
          string keys.
        * `:params` - The values of the SQL query's parameters, in order, as
          Druid received them. Dates and times are ISO 8601 strings. `nil`
          for a native query.
        * `:context` - The query context, with string keys.
      """
      defstruct [:type, :query, :params, context: %{}]

      @type t :: %__MODULE__{
              type: :sql | :statement | :ingest | :native,
              query: String.t() | map(),
              params: list() | nil,
              context: map()
            }
    end

    @typedoc "A function that answers the repo's requests. See the module docs."
    @type stub :: (Request.t() -> term())

    @doc """
    Answers the requests sent to `name` with `fun` in this test. `name` is
    the name in the repo's `plug: {Req.Test, name}` config.

    Replaces any stub this process set for `name` before.
    """
    @spec stub(term(), stub()) :: :ok
    def stub(name, fun) when is_function(fun, 1) do
      # Holds the statements and tasks the stub has answered, which Druid's
      # follow-up requests ask about. It belongs to the test process, so it
      # goes away with the test, and is public so the processes the test
      # allows can use it.
      table = :ets.new(__MODULE__, [:set, :public])
      Req.Test.stub(name, &call(&1, fun, table))
    end

    defp call(conn, fun, table) do
      {body, conn} = read_body(conn, "")
      route(conn.method, conn.path_info, conn, body, fun, table)
    end

    defp read_body(conn, acc) do
      case Conn.read_body(conn) do
        {:ok, data, conn} -> {decode(acc <> data), conn}
        {:more, data, conn} -> read_body(conn, acc <> data)
      end
    end

    defp decode(""), do: nil
    defp decode(body), do: Jason.decode!(body)

    # The Broker's SQL API. Druid.Tasks asks it whether it lists a data source
    # after an ingestion, which it always does here.
    defp route("POST", ["druid", "v2", "sql"], conn, body, fun, _table) do
      if body["query"] == Druid.Tasks.broker_lists_sql() do
        json(conn, 200, [[1]])
      else
        request = sql_request(:sql, body)

        with_result(conn, request, fun.(request), fn result ->
          rows = rows!(result, request)

          case body["resultFormat"] do
            "arrayLines" -> send_resp(conn, 200, array_lines(rows))
            _ -> json(conn, 200, rows)
          end
        end)
      end
    end

    defp route("DELETE", ["druid", "v2", "sql", _query_id], conn, _body, _fun, _table),
      do: send_resp(conn, 202, "")

    # Queries from deep storage. The statement succeeds as soon as it's
    # submitted, so the repo doesn't wait to poll it.
    defp route("POST", ["druid", "v2", "sql", "statements"], conn, body, fun, table) do
      request = sql_request(:statement, body)
      id = "query-" <> (request.context["sqlQueryId"] || Ecto.UUID.generate())

      with_result(conn, request, fun.(request), fn
        {:failed, message} ->
          status = statement_status(id, "FAILED", %{"errorDetails" => failure(message)})
          :ets.insert(table, {{:statement, id}, status, []})
          json(conn, 200, status)

        result ->
          rows = rows!(result, request)
          status = statement_status(id, "SUCCESS", %{"result" => statement_result(rows)})
          :ets.insert(table, {{:statement, id}, status, rows})
          json(conn, 200, status)
      end)
    end

    defp route("GET", ["druid", "v2", "sql", "statements", id], conn, _body, _fun, table) do
      case :ets.lookup(table, {:statement, id}) do
        [{_key, status, _rows}] -> json(conn, 200, status)
        [] -> not_found(conn, "Query [#{id}] was not found")
      end
    end

    defp route("GET", ["druid", "v2", "sql", "statements", id, "results"], conn, _, _, table) do
      case :ets.lookup(table, {:statement, id}) do
        [{_key, _status, rows}] -> json(conn, 200, rows)
        [] -> not_found(conn, "Query [#{id}] was not found")
      end
    end

    defp route("DELETE", ["druid", "v2", "sql", "statements", _id], conn, _body, _fun, _table),
      do: send_resp(conn, 202, "")

    # SQL-based ingestion runs as a task, which has finished by the time the
    # repo first asks about it.
    defp route("POST", ["druid", "v2", "sql", "task"], conn, body, fun, table) do
      request = sql_request(:ingest, body)
      id = "query-" <> (request.context["sqlQueryId"] || Ecto.UUID.generate())

      with_result(conn, request, fun.(request), fn result ->
        outcome =
          case result do
            :ok -> {"SUCCESS", nil, nil}
            {:ok, rows} when is_integer(rows) -> {"SUCCESS", rows, nil}
            {:failed, message} -> {"FAILED", nil, message}
            other -> bad_result!(other, request, ":ok, {:ok, rows} or {:failed, message}")
          end

        :ets.insert(table, {{:task, id}, outcome, target(request.query)})
        json(conn, 200, %{"taskId" => id, "state" => "RUNNING"})
      end)
    end

    defp route("GET", ["druid", "indexer", "v1", "task", id, "status"], conn, _, _, table) do
      case :ets.lookup(table, {:task, id}) do
        [{_key, {state, _rows, message}, data_source}] ->
          status =
            %{
              "id" => id,
              "type" => "query_controller",
              "status" => state,
              "statusCode" => state,
              "duration" => 0,
              "dataSource" => data_source
            }
            |> put_present("errorMsg", message)

          json(conn, 200, %{"task" => id, "status" => status})

        [] ->
          json(conn, 404, %{"task" => id, "status" => nil})
      end
    end

    defp route("GET", ["druid", "indexer", "v1", "task", id, "reports"], conn, _, _, table) do
      case :ets.lookup(table, {:task, id}) do
        [{_key, {state, rows, _message}, _data_source}] ->
          payload =
            if rows,
              do: %{"counters" => %{"0" => %{"0" => rows_pushed(rows)}}},
              else: %{}

          report = %{
            "multiStageQuery" => %{
              "taskId" => id,
              "payload" => Map.put(payload, "status", %{"status" => state})
            }
          }

          json(conn, 200, report)

        [] ->
          not_found(conn, "Task [#{id}] was not found")
      end
    end

    defp route("POST", ["druid", "indexer", "v1", "task", id, "shutdown"], conn, _, _, _),
      do: json(conn, 200, %{"task" => id})

    # Asked when waiting for an ingestion's segments, which are all loaded
    defp route(
           "GET",
           ["druid", "coordinator", "v1", "datasources", data_source, "loadstatus"],
           conn,
           _body,
           _fun,
           _table
         ) do
      json(conn, 200, %{URI.decode(data_source) => 0})
    end

    # Native queries
    defp route("POST", ["druid", "v2"], conn, body, fun, _table) do
      request = %Request{type: :native, query: body, context: body["context"] || %{}}

      with_result(conn, request, fun.(request), fn
        {:raw, response} ->
          json(conn, 200, response)

        rows when is_list(rows) ->
          if Ecto.Druid.Native.flattens?(body),
            do: json(conn, 200, native_response(rows, body)),
            else: json(conn, 200, encode(rows))

        response ->
          json(conn, 200, encode(response))
      end)
    end

    defp route("DELETE", ["druid", "v2", _query_id], conn, _body, _fun, _table),
      do: send_resp(conn, 202, "")

    defp route(method, _path_info, conn, _body, _fun, _table) do
      raise ArgumentError,
            "Ecto.Druid.Test doesn't stub #{method} #{conn.request_path}. It answers the " <>
              "SQL, deep storage, ingestion and native queries a repo sends. Stub other " <>
              "Druid APIs with your own plug and Req.Test"
    end

    defp sql_request(type, body) do
      %Request{
        type: type,
        query: body["query"],
        params: Enum.map(body["parameters"] || [], & &1["value"]),
        context: body["context"] || %{}
      }
    end

    # The answers every request type takes, then the type's own
    defp with_result(conn, _request, :timeout, _fun),
      do: Req.Test.transport_error(conn, :timeout)

    defp with_result(conn, _request, {:error, category, message}, _fun)
         when is_atom(category) and is_binary(message) do
      {status, code} = error_status(category)

      body = %{
        "error" => "druidException",
        "errorCode" => code,
        "persona" => "USER",
        "category" => category |> Atom.to_string() |> String.upcase(),
        "errorMessage" => message,
        "context" => %{}
      }

      json(conn, status, body)
    end

    defp with_result(_conn, %Request{type: type} = request, {:failed, _} = result, _fun)
         when type not in [:statement, :ingest] do
      bad_result!(result, request, "rows, {:error, category, message} or :timeout")
    end

    defp with_result(_conn, _request, result, fun), do: fun.(result)

    # Druid's error categories, with the HTTP status each is sent with and
    # the errorCode most errors in it have
    @categories %{
      defensive: {500, "defensive"},
      invalid_input: {400, "invalidInput"},
      unauthorized: {401, "unauthorized"},
      forbidden: {403, "forbidden"},
      capacity_exceeded: {429, "capacityExceeded"},
      canceled: {500, "canceled"},
      runtime_failure: {500, "runtimeFailure"},
      timeout: {504, "timeout"},
      unsupported: {501, "unsupported"},
      uncategorized: {500, "uncategorized"},
      not_found: {404, "notFound"}
    }

    defp error_status(category) do
      case Map.fetch(@categories, category) do
        {:ok, status} ->
          status

        :error ->
          raise ArgumentError,
                "unknown Druid error category #{inspect(category)}, expected one of " <>
                  (@categories |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &inspect/1))
      end
    end

    defp failure(message) do
      %{
        "error" => "druidException",
        "errorCode" => "runtimeFailure",
        "persona" => "USER",
        "category" => "RUNTIME_FAILURE",
        "errorMessage" => message
      }
    end

    defp not_found(conn, message) do
      json(conn, 404, %{
        "error" => "druidException",
        "errorCode" => "notFound",
        "persona" => "USER",
        "category" => "NOT_FOUND",
        "errorMessage" => message
      })
    end

    defp rows!(rows, request) when is_list(rows) do
      Enum.map(rows, fn
        row when is_list(row) ->
          encode(row)

        row ->
          raise ArgumentError,
                "expected each row of a #{inspect(request.type)} result to be a list of " <>
                  "values in the order the query selects them, got: #{inspect(row)}"
      end)
    end

    defp rows!(other, request) do
      bad_result!(other, request, "a list of rows, {:error, category, message} or :timeout")
    end

    defp bad_result!(result, request, expected) do
      raise ArgumentError,
            "expected the stub to return #{expected} for a #{inspect(request.type)} " <>
              "request, got: #{inspect(result)}"
    end

    # One row per line, then a blank line, which tells a complete response
    # from one cut short. Druid sends a lone blank line for no rows.
    defp array_lines([]), do: "\n\n"
    defp array_lines(rows), do: Enum.map_join(rows, &[Jason.encode!(&1), "\n"]) <> "\n"

    defp statement_status(id, state, fields) do
      Map.merge(
        %{
          "queryId" => id,
          "state" => state,
          "createdAt" => format_datetime(DateTime.utc_now()),
          "durationMs" => 0
        },
        fields
      )
    end

    defp statement_result(rows) do
      pages =
        if rows == [],
          do: [],
          else: [%{"id" => 0, "numRows" => length(rows), "sizeInBytes" => 0}]

      %{
        "numTotalRows" => length(rows),
        "totalSizeInBytes" => 0,
        "dataSource" => "__query_select",
        "pages" => pages
      }
    end

    defp rows_pushed(rows), do: %{"segmentGenerationProgress" => %{"rowsPushed" => rows}}

    # The data source an INSERT or REPLACE writes to, which the task's status
    # reports
    defp target(sql) do
      case Regex.run(
             ~r/\A\s*(?:INSERT|REPLACE)\s+INTO\s+((?:"(?:[^"]|"")*"\.)*)("(?:[^"]|"")*"|[^\s.]+)/i,
             sql
           ) do
        [_, _prefix, ~s(") <> _ = quoted] ->
          quoted |> String.slice(1..-2//1) |> String.replace(~s(""), ~s("))

        [_, _prefix, name] ->
          name

        nil ->
          nil
      end
    end

    # The response Druid sends for a native query whose results are `rows`,
    # which Ecto.Druid.Native.rows/3 flattens back into them
    defp native_response(rows, query) do
      rows = Enum.map(rows, &stringify_row/1)

      case query["queryType"] do
        "timeseries" ->
          Enum.map(rows, fn row ->
            {time, result} = Map.pop(row, "__time")
            %{"timestamp" => time, "result" => result}
          end)

        "topN" ->
          rows
          |> Enum.chunk_by(& &1["__time"])
          |> Enum.map(fn [first | _] = bucket ->
            %{
              "timestamp" => first["__time"],
              "result" => Enum.map(bucket, &Map.delete(&1, "__time"))
            }
          end)

        "groupBy" ->
          if get_in(query, ["context", "resultAsArray"]) do
            columns = group_by_columns(query)
            Enum.map(rows, &values(&1, columns))
          else
            Enum.map(rows, fn row ->
              {time, event} = Map.pop(row, "__time")
              %{"version" => "v1", "timestamp" => time || interval_start(query), "event" => event}
            end)
          end

        "scan" when rows == [] ->
          []

        "scan" ->
          columns =
            case {query["columns"], hd(rows)} do
              {[_ | _] = columns, _row} -> columns
              {_columns, row} when is_map(row) -> Map.keys(row)
              _ -> nil
            end

          events =
            if query["resultFormat"] == "compactedList",
              do: Enum.map(rows, &values(&1, columns)),
              else: rows

          [%{"segmentId" => "ecto_druid_test", "columns" => columns, "events" => events}]

        # windowOperator results are arrays, so the stub returns them as such
        _ ->
          rows
      end
    end

    defp stringify_row(row) when is_map(row),
      do: Map.new(row, fn {key, value} -> {to_string(key), encode(value)} end)

    defp stringify_row(row) when is_list(row), do: encode(row)

    defp values(row, columns) when is_map(row), do: Enum.map(columns, &Map.get(row, &1))
    defp values(row, _columns) when is_list(row), do: row

    # The order Druid sends a resultAsArray groupBy's values in
    defp group_by_columns(query) do
      time = if all_granularity?(query), do: [], else: ["__time"]
      dimensions = Enum.map(query["dimensions"] || [], &dimension_name/1)
      outputs = (query["aggregations"] || []) ++ (query["postAggregations"] || [])
      time ++ dimensions ++ Enum.map(outputs, & &1["name"])
    end

    defp dimension_name(dimension) when is_binary(dimension), do: dimension
    defp dimension_name(%{"outputName" => name}) when is_binary(name), do: name
    defp dimension_name(%{"dimension" => name}), do: name

    defp all_granularity?(query) do
      query["granularity"] in [nil, "all", %{"type" => "all"}]
    end

    defp interval_start(query) do
      case query["intervals"] do
        [interval | _] when is_binary(interval) -> interval |> String.split("/") |> hd()
        _ -> "1970-01-01T00:00:00.000Z"
      end
    end

    # Values as Druid sends them: timestamps (and dates) with milliseconds and
    # an offset, decimals as numbers, and error bounds as arrays
    defp encode(%DateTime{} = value), do: format_datetime(value)

    defp encode(%NaiveDateTime{} = value),
      do: value |> DateTime.from_naive!("Etc/UTC") |> format_datetime()

    defp encode(%Date{} = value),
      do: value |> NaiveDateTime.new!(~T[00:00:00]) |> encode()

    defp encode(%Decimal{} = value),
      do: value |> Decimal.to_string(:normal) |> Jason.Fragment.new()

    defp encode(%Ecto.Druid.Estimate{value: value, lower_bound: lower, upper_bound: upper}),
      do: [value, lower, upper]

    defp encode(value) when is_list(value), do: Enum.map(value, &encode/1)

    defp encode(value) when is_map(value) and not is_struct(value),
      do: Map.new(value, fn {key, value} -> {key, encode(value)} end)

    defp encode(value), do: value

    defp format_datetime(%DateTime{microsecond: {microsecond, _}} = value) do
      millisecond = div(microsecond, 1000) * 1000
      DateTime.to_iso8601(%{value | microsecond: {millisecond, 3}})
    end

    defp put_present(map, _key, nil), do: map
    defp put_present(map, key, value), do: Map.put(map, key, value)

    defp json(conn, status, body) do
      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.send_resp(status, Jason.encode!(body))
    end

    defp send_resp(conn, status, body) do
      conn
      |> Conn.put_resp_content_type("application/json")
      |> Conn.send_resp(status, body)
    end
  end
end
