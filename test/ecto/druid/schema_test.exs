defmodule Ecto.Druid.SchemaTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid.PageViews
  alias Ecto.Druid.Schema.Spec

  describe "Ecto fields" do
    test "defines a normal Ecto schema" do
      assert PageViews.__schema__(:source) == "ecto_druid_page_views_test"

      assert PageViews.__schema__(:fields) ==
               [:time, :country, :browser, :tags, :duration_ms, :attributes] ++
                 [:visitor_key, :user_agent, :referrer, :views] ++
                 [:watch_time, :max_duration, :sessions, :visitors, :load_times] ++
                 [:scroll_depth, :page_title]

      assert PageViews.__schema__(:type, :time) == Ecto.Druid.DateTime
      assert PageViews.__schema__(:field_source, :time) == :__time
      assert PageViews.__schema__(:field_source, :browser) == :browser_name
      assert PageViews.__schema__(:type, :visitors) == Ecto.Druid.HLLSketch
    end

    test "queries through the schema like any other" do
      import Ecto.Query

      start_supervised!(Ecto.Adapters.Druid.TestRepo)

      {sql, _} =
        Ecto.Adapters.Druid.TestRepo.to_sql(from(p in PageViews, select: {p.time, p.browser}))

      assert sql =~ ~s(SELECT e0."__time", e0."browser_name" FROM "ecto_druid_page_views_test")
    end
  end

  test "timestamp_spec/1" do
    assert Spec.timestamp_spec(PageViews) == %{"column" => "ts", "format" => "millis"}
  end

  test "dimensions_spec/1 keeps definition order and skips plain fields" do
    assert Spec.dimensions_spec(PageViews) == %{
             "dimensions" => [
               %{"type" => "string", "name" => "country"},
               %{"type" => "string", "name" => "browser_name"},
               %{"type" => "string", "name" => "tags"},
               %{"type" => "long", "name" => "duration_ms"},
               %{"type" => "auto", "name" => "attributes"},
               %{"type" => "string", "name" => "visitor_key"},
               %{"type" => "string", "name" => "user_agent"},
               %{"type" => "string", "name" => "referrer"}
             ]
           }
  end

  test "transforms/1 copies renamed input fields, quoting their names" do
    # referrer reads its own name, so it needs no transform
    assert Spec.transforms(PageViews) == [
             %{"type" => "expression", "name" => "visitor_key", "expression" => ~s("user_key")},
             %{"type" => "expression", "name" => "user_agent", "expression" => ~s("user-agent")}
           ]
  end

  test "transforms/1 escapes quotes and backslashes in input field names" do
    [{module, _}] =
      Code.compile_string(~S"""
      defmodule Ecto.Druid.SchemaTest.OddNames do
        use Ecto.Druid.Schema
        @primary_key false
        schema "odd" do
          dimension :a, :string, from: ~s(say "hi")
          dimension :b, :string, from: "back\\slash"
        end
      end
      """)

    assert Enum.map(Spec.transforms(module), & &1["expression"]) ==
             [~S("say \"hi\""), ~S("back\\slash")]
  end

  test "metrics_spec/1 builds ingest aggregators" do
    assert Spec.metrics_spec(PageViews) == [
             %{"type" => "count", "name" => "views"},
             %{"type" => "doubleSum", "name" => "watch_time", "fieldName" => "watch_seconds"},
             %{"type" => "longMax", "name" => "max_duration", "fieldName" => "duration_ms"},
             %{
               "type" => "thetaSketch",
               "name" => "sessions",
               "fieldName" => "session_id",
               "size" => 8192
             },
             %{
               "type" => "HLLSketchBuild",
               "name" => "visitors",
               "fieldName" => "visitor_id",
               "lgK" => 12
             },
             %{
               "type" => "quantilesDoublesSketch",
               "name" => "load_times",
               "fieldName" => "load_ms",
               "k" => 128
             },
             %{
               "type" => "fixedBucketsHistogram",
               "name" => "scroll_depth",
               "fieldName" => "scroll_pct",
               "lowerLimit" => 0,
               "upperLimit" => 100,
               "numBuckets" => 10,
               "outlierHandlingMode" => "overflow"
             }
           ]
  end

  test "metrics_spec/2 with combining: true re-aggregates stored columns" do
    combining = Spec.metrics_spec(PageViews, combining: true)

    assert Enum.map(combining, &{&1["type"], &1["name"], &1["fieldName"]}) == [
             {"longSum", "views", "views"},
             {"doubleSum", "watch_time", "watch_time"},
             {"longMax", "max_duration", "max_duration"},
             {"thetaSketch", "sessions", "sessions"},
             {"HLLSketchMerge", "visitors", "visitors"},
             {"quantilesDoublesSketch", "load_times", "load_times"},
             {"fixedBucketsHistogram", "scroll_depth", "scroll_depth"}
           ]
  end

  describe "data_schema/2" do
    test "assembles the whole dataSchema" do
      data_schema = Spec.data_schema(PageViews)

      assert data_schema["dataSource"] == "ecto_druid_page_views_test"
      assert data_schema["timestampSpec"] == Spec.timestamp_spec(PageViews)
      assert data_schema["dimensionsSpec"] == Spec.dimensions_spec(PageViews)
      assert data_schema["metricsSpec"] == Spec.metrics_spec(PageViews)

      assert data_schema["granularitySpec"] == %{
               "type" => "uniform",
               "segmentGranularity" => "HOUR",
               "queryGranularity" => "NONE",
               "rollup" => true
             }

      assert data_schema["transformSpec"] == %{"transforms" => Spec.transforms(PageViews)}
    end

    test "takes granularity, transforms, filter and extra fields" do
      filter = %{"type" => "selector", "dimension" => "country", "value" => "US"}
      transform = %{"type" => "expression", "name" => "country", "expression" => "upper(country)"}

      data_schema =
        Spec.data_schema(PageViews,
          data_source: "other",
          segment_granularity: "DAY",
          query_granularity: %{"type" => "period", "period" => "PT1H", "timeZone" => "EST"},
          rollup: false,
          transforms: [transform],
          filter: filter,
          merge: %{"dimensionsSpec" => %{"dimensionExclusions" => ["ip"]}}
        )

      assert data_schema["dataSource"] == "other"
      assert data_schema["granularitySpec"]["segmentGranularity"] == "DAY"
      assert data_schema["granularitySpec"]["queryGranularity"]["timeZone"] == "EST"
      assert data_schema["granularitySpec"]["rollup"] == false

      assert data_schema["transformSpec"] == %{
               "transforms" => Spec.transforms(PageViews) ++ [transform],
               "filter" => filter
             }

      assert data_schema["dimensionsSpec"]["dimensionExclusions"] == ["ip"]
      assert length(data_schema["dimensionsSpec"]["dimensions"]) == 8
    end

    test "raises when a transform clashes with a generated one" do
      transform = %{type: "expression", name: "visitor_key", expression: "lower(user_key)"}

      assert_raise ArgumentError, ~r/transforms \["visitor_key"\] clash/, fn ->
        Spec.data_schema(PageViews, transforms: [transform])
      end
    end

    test "rolls up only when there are metrics" do
      [{module, _}] =
        Code.compile_string("""
        defmodule Ecto.Druid.SchemaTest.NoMetrics do
          use Ecto.Druid.Schema
          @primary_key false
          schema "raw_events" do
            timestamp :time
            dimension :name, :string
          end
        end
        """)

      data_schema = Spec.data_schema(module)
      assert data_schema["granularitySpec"]["rollup"] == false
      assert data_schema["timestampSpec"] == %{"column" => "timestamp", "format" => "auto"}
      assert data_schema["metricsSpec"] == []
      refute Map.has_key?(data_schema, "transformSpec")
    end
  end

  describe "errors" do
    defp compile(body) do
      name = "Ecto.Druid.SchemaTest.Bad#{System.unique_integer([:positive])}"

      Code.compile_string("""
      defmodule #{name} do
        use Ecto.Druid.Schema
        @primary_key false
        schema "bad" do
          #{body}
        end
      end
      """)
    end

    test "a metric without an aggregate for its type" do
      assert_raise ArgumentError, ~r/\.total: can't aggregate :integer with nil/, fn ->
        compile("metric :total, :integer")
      end
    end

    test "summing a string" do
      assert_raise ArgumentError, ~r/can't aggregate :string with :sum/, fn ->
        compile("metric :name, :string, aggregate: :sum")
      end
    end

    test "a dimension type that can't be inferred" do
      assert_raise ArgumentError, ~r/\.at: can't infer a Druid dimension type/, fn ->
        compile("dimension :at, :utc_datetime")
      end
    end

    test "two timestamps" do
      assert_raise CompileError, ~r/more than one Druid timestamp/, fn ->
        compile("timestamp :a\ntimestamp :b")
      end
    end

    test "a schema that doesn't use Ecto.Druid.Schema" do
      assert_raise ArgumentError, ~r/must `use Ecto.Druid.Schema`/, fn ->
        Spec.data_schema(Ecto.Adapters.Druid.Wikipedia)
      end
    end

    test "data_schema/2 without a timestamp" do
      [{module, _}] = compile("dimension :name, :string")

      assert_raise ArgumentError, ~r/has no Druid timestamp/, fn ->
        Spec.data_schema(module)
      end
    end
  end
end
