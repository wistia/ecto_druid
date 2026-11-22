defmodule UpdateAllIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :druid

  import Ecto.Query
  alias Ecto.Adapters.Druid.IntegrationRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_update_all_test"

  # SQL-based ingestion runs as tasks, which take a while in the test cluster
  @moduletag timeout: 600_000

  defmodule Event do
    use Ecto.Druid.Schema
    @primary_key false
    schema "ecto_druid_update_all_test" do
      timestamp :time
      dimension :channel, :string
      dimension :category, :string
      dimension :tags, {:array, :string}, multi_value: true
      dimension :labels, {:array, :string}
      dimension :count, :integer
    end
  end

  setup do
    on_exit(fn ->
      Ecto.Druid.TestTasks.shutdown_all(@data_source)
      Druid.Client.DataSource.mark_unused(@data_source) |> Druid.Client.request(@druid)
    end)
  end

  # insert_all can't write multi-value columns, so the rows are written with
  # SQL. Rows with a nil tags or labels get a NULL one.
  defp ingest!(sql) do
    %{"taskId" => task_id} = Druid.Client.SQL.insert(sql) |> Druid.Client.request!(@druid)
    {:ok, _} = Druid.Tasks.await(IntegrationRepo, task_id, wait_for_segments: true)
  end

  # Druid checks the columns a statement names against the Broker's schema,
  # which picks up a new column a while after its segments load
  defp await_column!(column) do
    query =
      from c in Ecto.Druid.InformationSchema.Columns,
        where: c.table_name == ^@data_source and c.column_name == ^column,
        select: c.column_name

    check = fn -> if IntegrationRepo.one(query), do: {:done, column}, else: :wait end
    assert {:ok, ^column} = Druid.Poll.poll(Druid.Poll.deadline(120_000), 500, check)
  end

  defp rows do
    # Druid only orders scans by __time
    IntegrationRepo.all(
      from e in @data_source,
        select: {e.__time, e.channel, e.category, e.count, e.tags, e.labels}
    )
    |> Enum.map(fn {time, channel, category, count, tags, labels} ->
      {time, channel, category, count, multi_value(tags), labels}
    end)
    |> Enum.sort()
  end

  # Without a schema, Druid returns a multi-value string with one value as
  # that value, and with more as a JSON array
  defp multi_value(nil), do: nil
  defp multi_value("[" <> _ = values), do: Jason.decode!(values)
  defp multi_value(value), do: [value]

  test "backfills a new column on older rows, keeping the rest" do
    # Jan 1 was ingested before the category column existed
    ingest!("""
    REPLACE INTO "#{@data_source}" OVERWRITE ALL
    SELECT TIME_PARSE(ts) AS __time, channel, STRING_TO_MV(tags, ',') AS tags,
           STRING_TO_ARRAY(labels, ',') AS labels, "count"
    FROM (VALUES
      ('2026-01-01T01:00:00Z', 'a', 'x,y', 'p', 1),
      ('2026-01-01T02:00:00Z', 'a', CAST(NULL AS VARCHAR), CAST(NULL AS VARCHAR), 2),
      ('2026-01-01T03:00:00Z', 'b', 'x', 'q', 3),
      ('2026-01-01T04:00:00Z', CAST(NULL AS VARCHAR), 'x', 'r', 4)
    ) AS t(ts, channel, tags, labels, "count")
    PARTITIONED BY DAY
    """)

    ingest!("""
    INSERT INTO "#{@data_source}"
    SELECT TIME_PARSE('2026-01-02T01:00:00Z') AS __time, 'a' AS channel, 'dogs' AS category,
           STRING_TO_MV('x', ',') AS tags, STRING_TO_ARRAY('s', ',') AS labels, 5 AS "count"
    PARTITIONED BY DAY
    """)

    await_column!("category")
    jan_1 = Ecto.Druid.Interval.new(~D[2026-01-01], ~D[2026-01-02])

    # Only Jan 1's "a" rows change. Pushing onto a NULL array or multi-value
    # column gives one element, as in Postgres. Druid keeps multi-value
    # strings sorted, so "new" isn't last in tags.
    assert {0, nil} =
             IntegrationRepo.update_all(
               from(e in Event,
                 where: e.channel == ^"a",
                 update: [
                   set: [category: ^"cats"],
                   inc: [count: ^10],
                   push: [tags: ^"new", labels: ^"new"]
                 ]
               ),
               [],
               interval: jan_1,
               partitioned_by: :day,
               wait_for_segments: true
             )

    assert rows() == [
             {"2026-01-01T01:00:00.000Z", "a", "cats", 11, ["new", "x", "y"], ["p", "new"]},
             {"2026-01-01T02:00:00.000Z", "a", "cats", 12, ["new"], ["new"]},
             {"2026-01-01T03:00:00.000Z", "b", nil, 3, ["x"], ["q"]},
             {"2026-01-01T04:00:00.000Z", nil, nil, 4, ["x"], ["r"]},
             {"2026-01-02T01:00:00.000Z", "a", "dogs", 5, ["x"], ["s"]}
           ]

    # Without a where clause every row in the interval changes
    assert {0, nil} =
             IntegrationRepo.update_all(Event, [pull: [tags: "x"]],
               interval: jan_1,
               partitioned_by: :day,
               wait_for_segments: true
             )

    assert rows() == [
             {"2026-01-01T01:00:00.000Z", "a", "cats", 11, ["new", "y"], ["p", "new"]},
             {"2026-01-01T02:00:00.000Z", "a", "cats", 12, ["new"], ["new"]},
             {"2026-01-01T03:00:00.000Z", "b", nil, 3, nil, ["q"]},
             {"2026-01-01T04:00:00.000Z", nil, nil, 4, nil, ["r"]},
             {"2026-01-02T01:00:00.000Z", "a", "dogs", 5, ["x"], ["s"]}
           ]

    # Setting a multi-value column replaces all its values, not each one
    assert {0, nil} =
             IntegrationRepo.update_all(
               from(e in Event, where: e.channel == ^"b"),
               [set: [tags: ["m", "n"], labels: ["l"]]],
               interval: jan_1,
               partitioned_by: :day,
               wait_for_segments: true
             )

    assert rows() == [
             {"2026-01-01T01:00:00.000Z", "a", "cats", 11, ["new", "y"], ["p", "new"]},
             {"2026-01-01T02:00:00.000Z", "a", "cats", 12, ["new"], ["new"]},
             {"2026-01-01T03:00:00.000Z", "b", nil, 3, ["m", "n"], ["l"]},
             {"2026-01-01T04:00:00.000Z", nil, nil, 4, nil, ["r"]},
             {"2026-01-02T01:00:00.000Z", "a", "dogs", 5, ["x"], ["s"]}
           ]
  end
end
