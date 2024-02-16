defmodule Ecto.Adapters.Druid.Types do
  def dumpers(:binary_id, type), do: [Ecto.UUID, type]

  def loaders(:binary_id, type), do: [Ecto.UUID, type]
end
