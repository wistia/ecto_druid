defmodule SQLTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  test "aggregate to_sql" do
    assert TestRepo.to_sql(Wikipedia.by_page("Black Dhalia")) ==
             {"SELECT sum(w0.\"added\"), sum(w0.\"deleted\"), sum(w0.\"delta\"), APPROX_COUNT_DISTINCT_DS_THETA(w0.\"user\", 256), DS_HISTOGRAM(DS_QUANTILES_SKETCH(w0.\"delta\", 256), -30, -20, -10, 0, 10, 20, 30), DS_THETA(w0.\"user\", 256) FROM \"wikipedia\" AS w0 WHERE (w0.\"page\" = ?)",
              ["Black Dhalia"]}
  end

  test "timeseries to_sql" do
    assert TestRepo.to_sql(Wikipedia.over_time("1947-01-01 00:00:00Z/1947-12-31 23:59:59Z")) ==
             {
               "SELECT w0.\"__time\", w0.\"page\", sum(w0.\"added\"), sum(w0.\"deleted\"), sum(w0.\"delta\"), APPROX_COUNT_DISTINCT_DS_THETA(w0.\"user\", 256), DS_HISTOGRAM(DS_QUANTILES_SKETCH(w0.\"delta\", 256), -30, -20, -10, 0, 10, 20, 30), DS_THETA(w0.\"user\", 256) FROM \"wikipedia\" AS w0 WHERE (TIME_IN_INTERVAL(w0.\"__time\", ?)) GROUP BY w0.\"__time\", w0.\"page\" LIMIT 3",
               ["1947-01-01 00:00:00Z/1947-12-31 23:59:59Z"]
             }
  end
end
