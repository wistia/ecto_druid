defmodule Ecto.Druid.Native.BuildersTest do
  use ExUnit.Case, async: true

  import Ecto.Druid.Native.Expression
  alias Ecto.Druid.Native.{Aggregator, Filter, PostAggregator}

  doctest Ecto.Druid.Native.Filter
  doctest Ecto.Druid.Native.Aggregator
  doctest Ecto.Druid.Native.PostAggregator

  describe "Filter" do
    test "equals works out the match value type" do
      assert Filter.equals("added", 3).matchValueType == "LONG"
      assert Filter.equals("delta", 1.5).matchValueType == "DOUBLE"
      assert Filter.equals("ns", [1, 2]).matchValueType == "ARRAY<LONG>"
      assert Filter.equals("isRobot", true, type: "LONG").matchValueType == "LONG"
    end

    test "equals asks for a type it can't work out" do
      assert_raise ArgumentError, ~r/Pass :type/, fn -> Filter.equals("isRobot", true) end
      assert_raise ArgumentError, ~r/Pass :type/, fn -> Filter.equals("tags", [1, "a"]) end
    end

    test "range needs a bound and one type" do
      assert_raise ArgumentError, ~r/needs a :lower or :upper/, fn ->
        Filter.range("added", [])
      end

      assert_raise ArgumentError, ~r/different types/, fn ->
        Filter.range("a", lower: 1, upper: "b")
      end

      assert Filter.range("a", lower: 1, upper: 2.5).matchValueType == "DOUBLE"
      assert Filter.range("a", lower: "a", type: "STRING").matchValueType == "STRING"
    end

    test "like takes an escape" do
      assert Filter.like("page", "100\\%", escape: "\\") ==
               %{type: "like", dimension: "page", pattern: "100\\%", escape: "\\"}
    end

    test "interval takes Ecto.Druid.Intervals and a column" do
      interval = Ecto.Druid.Interval.new(~D[2016-06-27], day: 1)

      assert %{dimension: "ts", intervals: [^interval]} =
               Filter.interval(interval, column: "ts")
    end

    test "selector takes an extraction function" do
      fun = %{type: "upper"}

      assert Filter.selector("page", "A", extraction_fn: fun) ==
               %{type: "selector", dimension: "page", value: "A", extractionFn: fun}
    end

    test "bound needs a bound and takes an ordering" do
      assert_raise ArgumentError, ~r/needs a :lower or :upper/, fn ->
        Filter.bound("added", [])
      end

      assert Filter.bound("v", upper: "1.2", ordering: "version").ordering == "version"
      assert Filter.bound("added", upper: 1.5).ordering == "numeric"
      refute Map.has_key?(Filter.bound("added", lower: 1, upper: "b"), :ordering)
    end

    test "and_ and or_ leave out nils" do
      a = Filter.null("a")
      b = Filter.null("b")

      assert Filter.and_([a, nil, b]) == %{type: "and", fields: [a, b]}
      assert Filter.or_([nil, a, b]) == %{type: "or", fields: [a, b]}
      assert Filter.and_([nil]) == nil
      assert Filter.or_([]) == nil
      assert Filter.not_(nil) == nil
    end
  end

  describe "Aggregator" do
    test "names the output" do
      assert Aggregator.long_sum("added", name: "total") ==
               %{type: "longSum", name: "total", fieldName: "added"}
    end

    test "aggregates an expression" do
      assert Aggregator.double_sum(expr(added * 2), name: "doubled") ==
               %{type: "doubleSum", name: "doubled", expression: expr(added * 2)}

      assert_raise ArgumentError, ~r/needs a :name/, fn ->
        Aggregator.long_sum(expr(added * 2))
      end
    end

    test "wraps filtered aggregators" do
      filter = Filter.equals("isRobot", "true")

      assert Aggregator.count("robots", filter: filter) ==
               %{type: "filtered", filter: filter, aggregator: %{type: "count", name: "robots"}}

      assert %{type: "filtered", aggregator: %{type: "longMax"}} =
               Aggregator.long_max("added", filter: filter)

      assert Aggregator.long_max("added", filter: nil) == Aggregator.long_max("added")
    end

    test "camelizes other options" do
      assert Aggregator.string_any("page", max_string_bytes: 128) ==
               %{type: "stringAny", name: "page", fieldName: "page", maxStringBytes: 128}
    end

    test "builds every numeric aggregator type" do
      for {fun, type} <- [
            long_sum: "longSum",
            long_min: "longMin",
            long_max: "longMax",
            long_first: "longFirst",
            long_last: "longLast",
            long_any: "longAny",
            double_sum: "doubleSum",
            double_min: "doubleMin",
            double_max: "doubleMax",
            double_first: "doubleFirst",
            double_last: "doubleLast",
            double_any: "doubleAny",
            float_sum: "floatSum",
            float_min: "floatMin",
            float_max: "floatMax",
            float_first: "floatFirst",
            float_last: "floatLast",
            float_any: "floatAny"
          ] do
        assert apply(Aggregator, fun, ["added"]).type == type
      end
    end

    test "merges HLL sketches" do
      assert Aggregator.hll_sketch("users", merge: true).type == "HLLSketchMerge"
    end
  end

  describe "PostAggregator" do
    test "arithmetic reads fields by name and passes post-aggregators through" do
      nested = PostAggregator.arithmetic("sum", :+, ["a", "b"])

      assert PostAggregator.arithmetic("r", "quotient", [nested, :c], ordering: "numericFirst") ==
               %{
                 type: "arithmetic",
                 name: "r",
                 fn: "quotient",
                 fields: [nested, %{type: "fieldAccess", fieldName: :c}],
                 ordering: "numericFirst"
               }
    end

    test "expression takes an output type" do
      assert PostAggregator.expression("r", "a / b", output_type: "DOUBLE") ==
               %{type: "expression", name: "r", expression: "a / b", outputType: "DOUBLE"}
    end

    test "field_access and constant take a name" do
      assert PostAggregator.field_access("a", name: "b") ==
               %{type: "fieldAccess", fieldName: "a", name: "b"}

      assert PostAggregator.constant(1, name: "one") == %{type: "constant", value: 1, name: "one"}
    end
  end
end
