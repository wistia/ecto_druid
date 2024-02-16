defmodule Ecto.Adapters.Druid.Type do
  def dumpers(:binary_id, type), do: [Ecto.UUID, type]

  def loaders(:binary_id, type), do: [Ecto.UUID, type]
end
