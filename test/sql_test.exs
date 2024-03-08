defmodule SQLTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  test "to_sql" do
    assert TestRepo.to_sql(Wikipedia.by_page("Black Dhalia")) ==
             {"SELECT sum(w0.\"added\"), sum(w0.\"deleted\"), sum(w0.\"delta\"), APPROX_COUNT_DISTINCT_DS_THETA(w0.\"user\", 256), DS_HISTOGRAM(DS_QUANTILES_SKETCH(w0.\"delta\", 256), -30, -20, -10, 0, 10, 20, 30), DS_THETA(w0.\"user\", 256) FROM \"wikipedia\" AS w0 WHERE (w0.\"page\" = ?)",
              ["Black Dhalia"]}
  end
end
