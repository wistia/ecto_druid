defmodule Ecto.Druid.Estimate do
  @moduledoc """
  A distinct count estimate with its error bounds, as
  `Ecto.Druid.Query.HLL.hll_sketch_estimate_with_error_bounds/1` and
  `Ecto.Druid.Query.Theta.theta_sketch_estimate_with_error_bounds/2` return.

      %Ecto.Druid.Estimate{value: 3.000000014901161, lower_bound: 3.0, upper_bound: 3.0001498026537594}

  The bounds are the given number of standard deviations from the estimate.
  """
  @behaviour Ecto.Type

  @enforce_keys [:value, :lower_bound, :upper_bound]
  defstruct [:value, :lower_bound, :upper_bound]

  @type t :: %__MODULE__{value: float, lower_bound: float, upper_bound: float}

  # :complex so the adapter doesn't wrap the functions in a CAST
  @impl Ecto.Type
  def type, do: :complex

  @impl Ecto.Type
  def cast(%__MODULE__{} = estimate), do: {:ok, estimate}
  def cast(_value), do: :error

  @impl Ecto.Type
  def embed_as(_format), do: :self

  @impl Ecto.Type
  def equal?(value1, value2), do: value1 == value2

  # HLL returns [estimate, lower, upper], and theta a JSON-encoded object
  @impl Ecto.Type
  def load([value, lower, upper])
      when is_number(value) and is_number(lower) and is_number(upper) do
    {:ok, %__MODULE__{value: value / 1, lower_bound: lower / 1, upper_bound: upper / 1}}
  end

  def load(%{"estimate" => value, "lowBound" => lower, "highBound" => upper}),
    do: load([value, lower, upper])

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> load(decoded)
      _ -> :error
    end
  end

  def load(_value), do: :error

  # Druid has no parameter type for an estimate
  @impl Ecto.Type
  def dump(_value), do: :error
end
