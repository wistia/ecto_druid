defmodule Ecto.Druid.DSHistogram do
  @moduledoc """
  An `Ecto.Type` for the arrays of doubles that `DS_GET_QUANTILES`,
  `DS_HISTOGRAM`, `DS_CDF` and `FIXED_BUCKETS_HISTOGRAM_QUANTILES` return.

  Its database type is `:complex`, like the sketches, so the adapter doesn't
  wrap those functions in a `CAST`.
  """
  @behaviour Ecto.Type

  @impl Ecto.Type
  def type, do: :complex

  @impl Ecto.Type
  def cast(value), do: Ecto.Type.cast({:array, :float}, value)

  @impl Ecto.Type
  def embed_as(_format), do: :self

  @impl Ecto.Type
  def equal?(value1, value2), do: value1 == value2

  @impl Ecto.Type
  # Druid returns the array JSON-encoded, as "[0.0,1.0]"
  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> load(decoded)
      {:error, _} -> :error
    end
  end

  def load(value), do: Ecto.Type.load({:array, :float}, value)

  @impl Ecto.Type
  def dump(value), do: Ecto.Type.dump({:array, :float}, value)
end
