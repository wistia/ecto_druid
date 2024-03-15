defmodule Ecto.Druid.DateTime do
  @behaviour Ecto.Type

  # Elixir type database returns
  @impl true
  def type do
    :string
  end

  @impl true
  def equal?(value1, value2) do
    value1 == value2
  end

  @impl true
  def embed_as(_format) do
    :dump
  end

  @impl true
  def load(value) when is_binary(value) do
    with {:ok, datetime, _} <- DateTime.from_iso8601(value) do
      {:ok, datetime}
    else
      {:error, _} -> :error
    end
  end

  def load(_value) do
    :error
  end

  @impl true
  def dump(value) when is_struct(value, DateTime) do
    {:ok, DateTime.to_iso8601(value)}
  end

  def dump(_value) do
    :error
  end

  @impl true
  def cast(value) when is_binary(value) do
    with {:ok, datetime, _} <- DateTime.from_iso8601(value) do
      {:ok, datetime}
    else
      {:error, _} -> :error
    end
  end

  def cast(value) when is_struct(value, DateTime) do
    value
  end

  def cast(value) when is_integer(value) do
    with {:error, _} <- DateTime.from_unix(value) do
      :error
    end
  end

  def cast(_value) do
    :error
  end
end
