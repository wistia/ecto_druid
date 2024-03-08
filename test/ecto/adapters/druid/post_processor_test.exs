defmodule Ecto.Adapters.Druid.PostProcessorTest do
  use ExUnit.Case

  describe "process_results/1" do
    test "process_result/1 with complex types" do
      header = ["__time", "page", "delta_histogram", "unique_users"]
      types = ["LONG", "STRING", "COMPLEX", "COMPLEX<thetaSketch>"]

      rows = [
        [1, "page1", "[1, 2, 3]", "\"AQMDAAA6zJOFHZZiGEjVRw==\""],
        [2, "page1", "[4, 5, 6]", "\"AQMDAAA6zJOFHZZiGEjVRw==\""]
      ]

      assert Ecto.Adapters.Druid.PostProcessor.process_result([header, types | rows]) == [
               [1, "page1", [1, 2, 3], "AQMDAAA6zJOFHZZiGEjVRw=="],
               [2, "page1", [4, 5, 6], "AQMDAAA6zJOFHZZiGEjVRw=="]
             ]
    end
  end
end
