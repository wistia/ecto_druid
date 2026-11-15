defmodule Ecto.Adapters.Druid.Types do
  @moduledoc false

  # Map elixir type to database type. Dumpers run in order, so custom types
  # (whose primitive type is passed as the first argument) must dump through
  # their own module rather than through the primitive type.
  def dumpers(:binary_id, value), do: [Ecto.UUID, value]
  def dumpers(:complex, value), do: [:string, value]
  def dumpers(_type, ecto_type), do: [ecto_type]

  # Map database type to elixir type
  def loaders(:binary_id, value), do: [Ecto.UUID, value]
  def loaders(:complex, value), do: [:string, value]
  def loaders(type, value), do: [type, value]

  # Type names must be Avatica SqlType values.
  def to_db(value) when is_integer(value), do: db("BIGINT", value)
  def to_db(value) when is_float(value), do: db("DOUBLE", value)
  def to_db(value) when is_binary(value), do: db("VARCHAR", value)
  def to_db(value) when is_boolean(value), do: db("BOOLEAN", value)
  def to_db(%DateTime{} = value), do: db("TIMESTAMP", DateTime.to_iso8601(value))
  def to_db(%NaiveDateTime{} = value), do: db("TIMESTAMP", NaiveDateTime.to_iso8601(value))

  defp db(type, value), do: %{type: type, value: value}
end
