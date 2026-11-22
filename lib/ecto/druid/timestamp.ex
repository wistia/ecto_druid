defmodule Ecto.Druid.Timestamp do
  @moduledoc """
  An Ecto type for Druid's `__time` column. The `timestamp` field of an
  `Ecto.Druid.Schema` has this type.

  Values load and cast as `DateTime` structs, like `Ecto.Druid.DateTime`,
  but are sent to Druid as `TIMESTAMP` parameters, which SQL-based ingestion
  needs for `__time`. Use `Ecto.Druid.DateTime` for columns that hold times
  as strings, such as those of the system tables.

      field :time, Ecto.Druid.Timestamp, source: :__time
  """

  use Ecto.Type

  @impl Ecto.Type
  def type, do: :utc_datetime_usec

  # The adapter loads Druid's ISO 8601 strings into DateTimes before this
  # runs. Other sources may pass the string itself.
  @impl Ecto.Type
  def load(%DateTime{} = value), do: {:ok, value}
  def load(value), do: Ecto.Druid.DateTime.load(value)

  @impl Ecto.Type
  def dump(%DateTime{} = value), do: {:ok, value}
  def dump(_value), do: :error

  @impl Ecto.Type
  defdelegate cast(value), to: Ecto.Druid.DateTime
end
