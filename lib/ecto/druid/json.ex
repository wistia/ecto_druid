defmodule Ecto.Druid.JSON do
  @moduledoc """
  An Ecto type for JSON held in a Druid `VARCHAR` column.

  Druid's system tables return nested data, such as a segment's shard spec or
  a supervisor's spec, as JSON strings. This type decodes them on load and
  encodes them on dump, so they can be used as maps and lists.

      field :shard_spec, Ecto.Druid.JSON
  """

  @behaviour Ecto.Type

  @impl Ecto.Type
  def type, do: :string

  @impl Ecto.Type
  def embed_as(_format), do: :self

  @impl Ecto.Type
  def equal?(value1, value2), do: value1 == value2

  @impl Ecto.Type
  def cast(value) when is_binary(value), do: decode(value)
  def cast(value) when is_map(value) or is_list(value), do: {:ok, value}
  def cast(_value), do: :error

  @impl Ecto.Type
  def load(value) when is_binary(value), do: decode(value)
  def load(value) when is_map(value) or is_list(value), do: {:ok, value}
  def load(_value), do: :error

  @impl Ecto.Type
  def dump(value) do
    case Jason.encode(value) do
      {:ok, json} -> {:ok, json}
      {:error, _} -> :error
    end
  end

  defp decode(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> :error
    end
  end
end
