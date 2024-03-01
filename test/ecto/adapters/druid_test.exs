defmodule Ecto.Adapters.DruidTest do
  use ExUnit.Case
  doctest Ecto.Adapters.Druid
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  test "queries druid" do
    assert TestRepo.all(Wikipedia.by_page("Black Dahlia")) == []
  end

  test "to_sql" do
    assert TestRepo.to_sql(Wikipedia.by_page("home")) ==
             {"SELECT sum(w0.\"added\"), sum(w0.\"deleted\"), sum(w0.\"delta\"), APPROX_COUNT_DISTINCT_DS_THETA(w0.\"user\", 256), DS_HISTOGRAM(DS_QUANTILES_SKETCH(w0.\"delta\", 256), -1000, -500, -200, 0, 200, 500, 1000) FROM \"wikipedia\" AS w0 WHERE (w0.\"page\" = ?)",
              ["home"]}
  end

  # test "inserts" do
  #   assert TestRepo.insert_all(ConversionEvents, Seeds.conversion_events()) ==
  #            {1, [%{task_id: ""}]}
  # end
end
