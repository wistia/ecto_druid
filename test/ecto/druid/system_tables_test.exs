defmodule Ecto.Druid.SystemTablesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Druid.InformationSchema
  alias Ecto.Druid.Sys

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  test "sys tables are prefixed with the sys schema" do
    query =
      from s in Sys.Segments,
        where: s.datasource == ^"wikipedia" and s.is_active == 1,
        select: {s.segment_id, s.end}

    assert TestRepo.to_sql(query) ==
             {~s|SELECT s0."segment_id", s0."end" FROM "sys"."segments" AS s0 | <>
                ~s|WHERE ((s0."datasource" = ?) AND (s0."is_active" = 1))|, ["wikipedia"]}
  end

  test "sys tables can be joined" do
    query =
      from ss in Sys.ServerSegments,
        join: s in Sys.Servers,
        on: s.server == ss.server,
        select: {s.tier, ss.segment_id}

    assert {sql, []} = TestRepo.to_sql(query)
    assert sql =~ ~s|FROM "sys"."server_segments" AS s0 INNER JOIN "sys"."servers" AS s1|
  end

  test "INFORMATION_SCHEMA fields map to upper-case columns" do
    query =
      from c in InformationSchema.Columns,
        where: c.table_name == ^"wikipedia",
        order_by: c.ordinal_position,
        select: {c.column_name, c.data_type}

    assert TestRepo.to_sql(query) ==
             {~s|SELECT C0."COLUMN_NAME", C0."DATA_TYPE" FROM "INFORMATION_SCHEMA"."COLUMNS" AS C0 | <>
                ~s|WHERE (C0."TABLE_NAME" = ?) ORDER BY C0."ORDINAL_POSITION"|, ["wikipedia"]}
  end

  describe "Ecto.Druid.JSON" do
    test "loads JSON strings" do
      assert Ecto.Type.load(Ecto.Druid.JSON, ~s|{"type":"numbered","partitions":1}|) ==
               {:ok, %{"type" => "numbered", "partitions" => 1}}

      assert Ecto.Type.load(Ecto.Druid.JSON, ~s|["a","b"]|) == {:ok, ["a", "b"]}
      assert Ecto.Type.load(Ecto.Druid.JSON, nil) == {:ok, nil}
      assert Ecto.Type.load(Ecto.Druid.JSON, "not json") == :error
    end

    test "dumps to JSON strings" do
      assert Ecto.Type.dump(Ecto.Druid.JSON, %{"a" => 1}) == {:ok, ~s|{"a":1}|}
    end
  end
end
