defmodule Ecto.Druid.InformationSchema.Schemata do
  @moduledoc """
  The `INFORMATION_SCHEMA.SCHEMATA` table: the schemas Druid SQL exposes
  (`druid`, `lookup`, `sys`, `INFORMATION_SCHEMA`, and so on).

      from s in Ecto.Druid.InformationSchema.Schemata, select: s.schema_name

  Druid names these columns in upper case; the fields are their lower-case
  equivalents.

  See [the Druid docs](https://druid.apache.org/docs/latest/querying/sql-metadata-tables#schemata-table).
  """

  use Ecto.Schema

  @primary_key false
  @schema_prefix "INFORMATION_SCHEMA"
  schema "SCHEMATA" do
    field :catalog_name, :string, source: :CATALOG_NAME
    field :schema_name, :string, source: :SCHEMA_NAME
    field :schema_owner, :string, source: :SCHEMA_OWNER
    field :default_character_set_catalog, :string, source: :DEFAULT_CHARACTER_SET_CATALOG
    field :default_character_set_schema, :string, source: :DEFAULT_CHARACTER_SET_SCHEMA
    field :default_character_set_name, :string, source: :DEFAULT_CHARACTER_SET_NAME
    field :sql_path, :string, source: :SQL_PATH
  end
end
