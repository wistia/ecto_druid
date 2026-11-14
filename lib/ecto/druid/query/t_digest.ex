defmodule Ecto.Druid.Query.TDigest do
  @moduledoc """
  Druid [T-Digest sketch aggregations](https://druid.apache.org/docs/latest/development/extensions-contrib/tdigestsketch-quantiles).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @doc "Builds a T-Digest sketch on values produced by expr and returns the value for the quantile. Compression parameter (default value 100) determines the accuracy and size of the sketch. Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_quantile(expr, quantile_fraction)

  @doc "Builds a T-Digest sketch on values produced by expr and returns the value for the quantile. Compression parameter (default value 100) determines the accuracy and size of the sketch. Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_quantile(expr, quantile_fraction, compression)

  @doc "Builds a T-Digest sketch on values produced by expr. Compression parameter (default value 100) determines the accuracy and size of the sketch Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_generate_sketch(expr)

  @doc "Builds a T-Digest sketch on values produced by expr. Compression parameter (default value 100) determines the accuracy and size of the sketch Higher compression means higher accuracy but more space to store sketches."
  sql_function tdigest_generate_sketch(expr, compression)
end
