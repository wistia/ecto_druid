defmodule SystemTablesIntegrationTest do
  use ExUnit.Case

  @moduletag :druid

  import Ecto.Query

  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Druid.InformationSchema
  alias Ecto.Druid.Sys

  setup do
    start_supervised!(TestRepo)
    :ok
  end

  test "every system table loads" do
    for schema <- [
          Sys.Segments,
          Sys.ServerSegments,
          Sys.Servers,
          Sys.ServerProperties,
          Sys.Tasks,
          Sys.Supervisors,
          InformationSchema.Schemata,
          InformationSchema.Tables,
          InformationSchema.Columns,
          InformationSchema.Routines
        ] do
      assert is_list(TestRepo.all(from(s in schema, limit: 5))), inspect(schema)
    end
  end

  test "sys.segments decodes flags and JSON" do
    [segment | _] =
      TestRepo.all(
        from s in Sys.Segments, where: s.datasource == "wikipedia" and s.is_active == 1
      )

    assert segment.is_active == 1
    assert segment.is_overshadowed == 0
    assert is_binary(segment.start) and is_binary(segment.end)
    assert %{"type" => _} = segment.shard_spec
    assert segment.num_rows > 0
  end

  test "sys.servers loads start times" do
    servers = TestRepo.all(Sys.Servers)

    assert servers != []
    assert Enum.all?(servers, &match?(%DateTime{}, &1.start_time))
    assert Enum.any?(servers, &(&1.server_type == "broker"))
  end

  test "INFORMATION_SCHEMA lists schemas and columns" do
    schemas = TestRepo.all(from s in InformationSchema.Schemata, select: s.schema_name)
    assert "druid" in schemas
    assert "sys" in schemas

    columns =
      TestRepo.all(
        from c in InformationSchema.Columns,
          where: c.table_schema == "druid" and c.table_name == "wikipedia",
          order_by: c.ordinal_position,
          select: {c.column_name, c.data_type}
      )

    assert {"__time", "TIMESTAMP"} in columns
    assert {"page", "VARCHAR"} in columns
  end
end
