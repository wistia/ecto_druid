defmodule IntegrationTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.TestRepo
  alias Ecto.Adapters.Druid.Wikipedia

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  test "queries druid" do
    assert TestRepo.all(Wikipedia.by_page("Black Dahlia")) == [
             %{
               added: 3,
               deleted: 0,
               delta: 3,
               unique_users: 1,
               delta_histogram: [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0],
               ds_theta: "AQMDAAA6zJOFHZZiGEjVRw=="
             }
           ]
  end
end
