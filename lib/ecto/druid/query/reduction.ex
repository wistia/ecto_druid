defmodule Ecto.Druid.Query.Reduction do
  @moduledoc """
  Druid [reduction functions](https://druid.apache.org/docs/latest/querying/sql-scalar#reduction-functions).
  """
  import Ecto.Druid.Util, only: [sql_function: 1]

  @doc "Evaluates zero or more expressions and returns the maximum value based on comparisons as described above."
  sql_function greatest(exprs)

  @doc "Evaluates zero or more expressions and returns the minimum value based on comparisons as described above."
  sql_function least(exprs)
end
