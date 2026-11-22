defmodule WikiExplorer.Wiki.Edit do
  @moduledoc """
  One Wikipedia edit in the `wiki_edits` data source.

  `timestamp`, `dimension` and `metric` from `Ecto.Druid.Schema` define normal
  Ecto fields for queries, and also describe how each column is ingested.
  The ingestion task template, `priv/druid/tasks/wiki_edits.json.eex`,
  generates its `dataSchema` from them with `data_schema`, so the schema and
  the data source can't drift apart.

  Druid's column names are camelCase, so fields use `:source` to map them to
  snake_case.
  """
  use Ecto.Druid.Schema

  @primary_key false
  schema "wiki_edits" do
    # Druid's `__time` column, read from the input's ISO 8601 `timestamp`
    # field. Loaded as an Ecto.Druid.Timestamp.
    timestamp :time, column: "timestamp", format: "iso"

    dimension :channel, :string
    dimension :page, :string
    dimension :user, :string
    dimension :comment, :string
    dimension :namespace, :string
    dimension :country, :string, source: :countryName
    dimension :city, :string, source: :cityName
    # The input has JSON booleans for these. Druid stores them as string
    # dimensions holding "true" or "false".
    dimension :is_robot, :string, source: :isRobot
    dimension :is_anonymous, :string, source: :isAnonymous
    dimension :is_new, :string, source: :isNew
    dimension :is_minor, :string, source: :isMinor

    # The ingestion task turns rollup off, so every edit stays its own row and
    # these sums are each edit's own values. With rollup on, Druid would
    # combine edits that share a timestamp and dimensions into one row.
    metric :added, :integer, aggregate: :sum
    metric :deleted, :integer, aggregate: :sum
    metric :delta, :integer, aggregate: :sum
  end
end
