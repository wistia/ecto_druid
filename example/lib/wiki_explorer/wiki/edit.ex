defmodule WikiExplorer.Wiki.Edit do
  @moduledoc """
  One Wikipedia edit in the `wiki_edits` data source.

  The data source is loaded by `mix wiki_explorer.ingest` from
  `priv/druid/ingestion/wiki_edits.json`. Druid's column names are camelCase,
  so fields use `:source` to map them to snake_case.
  """
  use Ecto.Schema

  @primary_key false
  schema "wiki_edits" do
    # Druid's time column is `__time`. Ecto.Druid.DateTime loads it as a DateTime.
    field(:time, Ecto.Druid.DateTime, source: :__time)
    field(:channel, :string)
    field(:page, :string)
    field(:user, :string)
    field(:comment, :string)
    field(:namespace, :string)
    field(:country, :string, source: :countryName)
    field(:city, :string, source: :cityName)
    # Boolean flags are string dimensions holding "true" or "false"
    field(:is_robot, :string, source: :isRobot)
    field(:is_anonymous, :string, source: :isAnonymous)
    field(:is_new, :string, source: :isNew)
    field(:is_minor, :string, source: :isMinor)
    field(:added, :integer)
    field(:deleted, :integer)
    field(:delta, :integer)
  end
end
