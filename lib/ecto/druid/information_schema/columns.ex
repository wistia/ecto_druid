defmodule Ecto.Druid.InformationSchema.Columns do
  @moduledoc """
  The `INFORMATION_SCHEMA.COLUMNS` table: the columns of every table Druid SQL
  can query.

      from c in Ecto.Druid.InformationSchema.Columns,
        where: c.table_schema == "druid" and c.table_name == "wikipedia",
        order_by: c.ordinal_position,
        select: {c.column_name, c.data_type}

  Druid names these columns in upper case; the fields are their lower-case
  equivalents. `is_nullable` is `"YES"` or `"NO"`.

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#columns-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "INFORMATION_SCHEMA"
  schema "COLUMNS" do
    field :table_catalog, :string, source: :TABLE_CATALOG
    field :table_schema, :string, source: :TABLE_SCHEMA
    field :table_name, :string, source: :TABLE_NAME
    field :column_name, :string, source: :COLUMN_NAME
    field :ordinal_position, :integer, source: :ORDINAL_POSITION
    field :column_default, :string, source: :COLUMN_DEFAULT
    field :is_nullable, :string, source: :IS_NULLABLE
    field :data_type, :string, source: :DATA_TYPE
    field :character_maximum_length, :string, source: :CHARACTER_MAXIMUM_LENGTH
    field :character_octet_length, :string, source: :CHARACTER_OCTET_LENGTH
    field :numeric_precision, :integer, source: :NUMERIC_PRECISION
    field :numeric_precision_radix, :integer, source: :NUMERIC_PRECISION_RADIX
    field :numeric_scale, :integer, source: :NUMERIC_SCALE
    field :datetime_precision, :integer, source: :DATETIME_PRECISION
    field :character_set_name, :string, source: :CHARACTER_SET_NAME
    field :collation_name, :string, source: :COLLATION_NAME
    field :jdbc_type, :integer, source: :JDBC_TYPE
  end
end
