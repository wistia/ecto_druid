defmodule Ecto.Adapters.DruidTest do
  use ExUnit.Case
  doctest Ecto.Adapters.Druid
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.MediaEvents

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  test "queries druid" do
    TestRepo.all(MediaEvents.by_media_id(1, 2))
  end

  test "to_sql" do
    assert TestRepo.to_sql(MediaEvents.by_media_id(1, 2)) ==
             {"SELECT m0.\"account_id\", m0.\"media_id\", sum(m0.\"loads\"), sum(m0.\"plays\") FROM \"media_events\" AS m0 WHERE ((m0.\"account_id\" = $1) AND (m0.\"media_id\" = $2))",
              [1, 2]}
  end
end
