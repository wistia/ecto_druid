defmodule Ecto.Adapters.Druid.Types do
  # Map database type to elixir type
  def dumpers(:binary_id, value), do: [Ecto.UUID, value]
  def dumpers(:complex, value), do: [:string, value]
  def dumpers(type, value), do: [type, value]

  # Map database type to elixir type
  def loaders(:binary_id, value), do: [Ecto.UUID, value]
  def loaders(:complex, value), do: [:string, value]
  def loaders(type, value), do: [type, value]

  def to_db(value) when is_integer(value), do: db("LONG", value)
  def to_db(value) when is_float(value), do: db("DOUBLE", value)
  def to_db(value) when is_binary(value), do: db("VARCHAR", value)
  def to_db(value) when is_boolean(value), do: db("BOOLEAN", value)

  defp db(type, value), do: %{type: type, value: value}
end
