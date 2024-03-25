defmodule Druid.Client.SQL do
  @moduledoc """
  Builds requests for Druid's SQL API.
  """

  @doc """
  Builds a query request for Druid's SQL API.

  ## Examples

      Druid.Client.SQL.query("SELECT * FROM wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @query_path "/druid/v2/sql"
  @spec query(String.t(), list(), Keyword.t()) :: Req.Request.t()
  def query(query, params \\ [], opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    body = %{
      query: query,
      parameters: params,
      context:
        Map.merge(
          %{
            sqlQueryId: Ecto.UUID.generate(),
            sqlStringifyArrays: false,
            skipEmptyBuckets: false,
            enableWindowing: true
          },
          context
        ),
      resultFormat: "array",
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
      context:
        Map.merge(
          %{
            sqlQueryId: Ecto.UUID.generate(),
            sqlStringifyArrays: false,
            skipEmptyBuckets: false,
            enableWindowing: true
          },
          context
        )
    }

    Req.new(method: :post, url: @insert_path, json: body)
  end
end
