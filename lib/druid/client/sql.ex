defmodule Druid.Client.SQL do
  @moduledoc """
  Builds requests for Druid's SQL API.
  """

  @doc """
  Builds a query request for Druid's SQL API.

  ## Options

  * `:context` - A map of [SQL query context parameters](https://druid.apache.org/docs/latest/querying/sql-query-context),
    merged over the defaults (`sqlQueryId`, `sqlStringifyArrays`,
    `skipEmptyBuckets`, `enableWindowing`).
  * `:result_format` - `"array"` (the default), `"object"`, `"arrayLines"`,
    `"objectLines"`, or `"csv"`. The `"...Lines"` formats send one row per
    line, which can be read as it arrives, and end with a blank line, so a
    response cut short can be told from a complete one.

  ## Examples

      Druid.Client.SQL.query("SELECT * FROM wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8082)

      Druid.Client.SQL.query("SELECT * FROM wikipedia", [], context: %{sqlTimeZone: "America/New_York"})
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @query_path "/druid/v2/sql"
  @spec query(String.t(), list(), Keyword.t()) :: Req.Request.t()
  def query(query, params \\ [], opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    body = %{
      query: query,
      parameters: params,
      context: context(context),
      resultFormat: Keyword.get(opts, :result_format, "array"),
      header: false,
      typesHeader: false
    }

    Req.new(method: :post, url: @query_path, json: body)
  end

  @doc """
  Builds an insert request for Druid's SQL API.

  ## Examples

      sql = \"""
        INSERT INTO w000
        SELECT
          TIME_PARSE("timestamp") AS __time,
          isRobot,
          channel,
          flags,
          isUnpatrolled,
          page,
          diffUrl,
          added,
          comment,
          commentLength,
          isNew,
          isMinor,
          delta,
          isAnonymous,
          user,
          deltaBucket,
          deleted,
          namespace,
          cityName,
          countryName,
          regionIsoCode,
          metroCode,
          countryIsoCode,
          regionName
        FROM TABLE(
            EXTERN(
              '{"type":"http","uris":["https://druid.apache.org/data/wikipedia.json.gz"]}',
              '{"type":"json"}',
              '[{"name":"isRobot","type":"string"},{"name":"channel","type":"string"},{"name":"timestamp","type":"string"},{"name":"flags","type":"string"},{"name":"isUnpatrolled","type":"string"},{"name":"page","type":"string"},{"name":"diffUrl","type":"string"},{"name":"added","type":"long"},{"name":"comment","type":"string"},{"name":"commentLength","type":"long"},{"name":"isNew","type":"string"},{"name":"isMinor","type":"string"},{"name":"delta","type":"long"},{"name":"isAnonymous","type":"string"},{"name":"user","type":"string"},{"name":"deltaBucket","type":"long"},{"name":"deleted","type":"long"},{"name":"namespace","type":"string"},{"name":"cityName","type":"string"},{"name":"countryName","type":"string"},{"name":"regionIsoCode","type":"string"},{"name":"metroCode","type":"long"},{"name":"countryIsoCode","type":"string"},{"name":"regionName","type":"string"}]'
            )
          )
        PARTITIONED BY HOUR
        CLUSTERED BY channel
        \"""

      Druid.Client.SQL.insert(sql)
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @insert_path "/druid/v2/sql/task"
  @spec insert(String.t(), list(), Keyword.t()) :: Req.Request.t()
  def insert(query, params \\ [], opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    body = %{
      query: query,
      parameters: params,
      context: context(context)
    }

    Req.new(method: :post, url: @insert_path, json: body)
  end

  @doc """
  Builds a request to cancel a running query by its `sqlQueryId`. Druid
  responds with a 202 once the cancellation is accepted.

  To cancel a SQL-based ingestion query, use `Druid.Client.Task.shutdown/1`.
  To cancel a query from deep storage, use `Druid.Client.SQL.Statement.cancel/1`.

  ## Examples

      Druid.Client.SQL.cancel("my-query")
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @spec cancel(String.t()) :: Req.Request.t()
  def cancel(sql_query_id) do
    Req.new(method: :delete, url: Druid.Client.Util.path(@query_path, [sql_query_id]))
  end

  @doc false
  @spec context(map()) :: map()
  def context(context) do
    Map.merge(
      %{
        sqlQueryId: Ecto.UUID.generate(),
        sqlStringifyArrays: false,
        skipEmptyBuckets: false,
        enableWindowing: true
      },
      context
    )
  end
end
