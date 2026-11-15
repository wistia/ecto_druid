defmodule Ecto.Druid.InformationSchema.Tables do
  @moduledoc """
  The `INFORMATION_SCHEMA.TABLES` table: every table Druid SQL can query,
  including datasources (schema `druid`), lookups and system tables.

      from t in Ecto.Druid.InformationSchema.Tables,
        where: t.table_schema == "druid",
        select: t.table_name

  Druid names these columns in upper case; the fields are their lower-case
  equivalents. `is_joinable` and `is_broadcast` are `"YES"` or `"NO"`.

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#tables-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "INFORMATION_SCHEMA"
  schema "TABLES" do
    field :table_catalog, :string, source: :TABLE_CATALOG
    field :table_schema, :string, source: :TABLE_SCHEMA
    field :table_name, :string, source: :TABLE_NAME
    field :table_type, :string, source: :TABLE_TYPE
    field :is_joinable, :string, source: :IS_JOINABLE
    field :is_broadcast, :string, source: :IS_BROADCAST
  end
end
