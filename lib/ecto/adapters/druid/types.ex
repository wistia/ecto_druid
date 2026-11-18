defmodule Ecto.Adapters.Druid.Types do
  @moduledoc false

  @datetime_types [
    :date,
    :utc_datetime,
    :utc_datetime_usec,
    :naive_datetime,
    :naive_datetime_usec
  ]

  # Map elixir type to database type. Dumpers run in order, so custom types
  # (whose primitive type is passed as the first argument) must dump through
  # their own module rather than through the primitive type.
  def dumpers(:binary_id, value), do: [Ecto.UUID, value]
  def dumpers(:complex, value), do: [:string, value]
  def dumpers(_type, ecto_type), do: [ecto_type]

  # Map database type to elixir type
  def loaders(:binary_id, value), do: [Ecto.UUID, value]
  def loaders(:complex, value), do: [:string, value]

  def loaders(type, value) when type in @datetime_types,
    do: [&load_datetime(&1, type), value]

  def loaders(type, value), do: [type, value]

  # Druid returns DATE and TIMESTAMP values as ISO 8601 strings in UTC, such
  # as "2016-06-27T00:00:00.000Z"
  defp load_datetime(value, type) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, convert_datetime(datetime, type)}
      {:error, _} -> :error
    end
  end

  defp load_datetime(value, _type), do: {:ok, value}

  defp convert_datetime(datetime, :date), do: DateTime.to_date(datetime)

  defp convert_datetime(datetime, type) when type in [:naive_datetime, :naive_datetime_usec],
    do: DateTime.to_naive(datetime)

  defp convert_datetime(datetime, _type), do: datetime

  # Type names must be Avatica SqlType values.
  def to_db(value) when is_integer(value), do: db("BIGINT", value)
  def to_db(value) when is_float(value), do: db("DOUBLE", value)
  def to_db(value) when is_binary(value), do: db("VARCHAR", value)
  def to_db(value) when is_boolean(value), do: db("BOOLEAN", value)
  def to_db(nil), do: db("NULL", nil)
  def to_db(%DateTime{} = value), do: db("TIMESTAMP", DateTime.to_iso8601(value))
  def to_db(%NaiveDateTime{} = value), do: db("TIMESTAMP", NaiveDateTime.to_iso8601(value))
  def to_db(%Date{} = value), do: db("DATE", Date.to_iso8601(value))

  # Jason encodes a Decimal as a JSON string, which Druid can't plan as a
  # DECIMAL, so it is sent as a JSON number. Ecto pins datetime_add counts
  # as decimals.
  def to_db(%Decimal{} = value),
    do: db("DECIMAL", value |> Decimal.to_string(:normal) |> Jason.Fragment.new())

  def to_db(value) when is_list(value), do: db("ARRAY", Enum.map(value, &to_db(&1).value))

  defp db(type, value), do: %{type: type, value: value}
end
