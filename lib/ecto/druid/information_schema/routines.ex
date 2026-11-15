defmodule Ecto.Druid.InformationSchema.Routines do
  @moduledoc """
  The `INFORMATION_SCHEMA.ROUTINES` table: the SQL functions Druid supports.

      from r in Ecto.Druid.InformationSchema.Routines,
        where: r.is_aggregator == "YES",
        select: r.routine_name

  Druid names these columns in upper case; the fields are their lower-case
  equivalents. `is_aggregator` is `"YES"` or `"NO"`.

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#routines-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "INFORMATION_SCHEMA"
  schema "ROUTINES" do
    field :routine_catalog, :string, source: :ROUTINE_CATALOG
    field :routine_schema, :string, source: :ROUTINE_SCHEMA
    field :routine_name, :string, source: :ROUTINE_NAME
    field :routine_type, :string, source: :ROUTINE_TYPE
    field :is_aggregator, :string, source: :IS_AGGREGATOR
    field :signatures, :string, source: :SIGNATURES
  end
end
