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

    test "takes batch ingestion intervals" do
      interval = Ecto.Druid.Interval.new(~U[2026-11-01 00:00:00Z], ~U[2026-11-02 00:00:00Z])

      assert Spec.data_schema(PageViews, intervals: "2026-11-01/P1D")["granularitySpec"][
               "intervals"
             ] == ["2026-11-01/P1D"]

      assert [iso] =
               Spec.data_schema(PageViews, intervals: [interval])["granularitySpec"]["intervals"]

      assert iso == "2026-11-01T00:00:00Z/2026-11-02T00:00:00Z"
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

  defp compile_schema(body) do
    name = "Ecto.Druid.SchemaTest.Schema#{System.unique_integer([:positive])}"

    Code.compile_string("""
    defmodule #{name} do
      use Ecto.Druid.Schema
      @primary_key false
      schema "s" do
        #{body}
      end
    end
    """)
  end

  defmodule Edits do
    use Ecto.Druid.Schema

    @primary_key false
    schema "edits" do
      # Projections can come before the columns they use
      projection :channel_hourly,
        granularity: :hour,
        group_by: [:channel, :robot],
        aggregate: [
          added: {:sum, :added},
          edits: :count,
          users: {Ecto.Druid.HLLSketch, :user, lg_k: 14}
        ]

      timestamp :time
      dimension :channel, :string, source: :channel_name
      dimension :robot, :boolean
      dimension :user, :string
      dimension :added, :integer
      dimension :latency, :float
      metric :views, :integer, aggregate: :count
      metric :visitors, Ecto.Druid.HLLSketch, from: "visitor_id"

      projection :daily_totals,
        granularity: "P1D",
        aggregate: [
          views: {:sum, :views},
          visitors: {Ecto.Druid.HLLSketch, :visitors},
          slowest: {:max, :latency},
          mean_latency: {"doubleMean", :latency},
          first_user: {:first, :user},
          least_added: %{type: "longMin", fieldName: "added"}
        ],
        extra_field: true
    end
  end

  describe "projections" do
    test "projections/1 builds each projection, grouping by the time bucket first" do
      assert [channel_hourly, daily_totals] = Spec.projections(Edits)

      assert channel_hourly == %{
               "type" => "aggregate",
               "name" => "channel_hourly",
               "virtualColumns" => [
                 %{
                   "type" => "expression",
                   "name" => "__gran",
                   "expression" => "timestamp_floor(__time, 'PT1H')",
                   "outputType" => "LONG"
                 }
               ],
               "groupingColumns" => [
                 %{"type" => "long", "name" => "__gran"},
                 %{"type" => "string", "name" => "channel_name"},
                 %{"type" => "long", "name" => "robot"}
               ],
               "aggregators" => [
                 %{"type" => "longSum", "name" => "added", "fieldName" => "added"},
                 %{"type" => "count", "name" => "edits"},
                 %{
                   "type" => "HLLSketchBuild",
                   "name" => "users",
                   "fieldName" => "user",
                   "lgK" => 14
                 }
               ]
             }

      # Aggregations of metrics re-aggregate them, and the type picks the
      # aggregator. Other options pass through.
      assert daily_totals == %{
               "type" => "aggregate",
               "name" => "daily_totals",
               "virtualColumns" => [
                 %{
                   "type" => "expression",
                   "name" => "__gran",
                   "expression" => "timestamp_floor(__time, 'P1D')",
                   "outputType" => "LONG"
                 }
               ],
               "groupingColumns" => [%{"type" => "long", "name" => "__gran"}],
               "aggregators" => [
                 %{"type" => "longSum", "name" => "views", "fieldName" => "views"},
                 %{"type" => "HLLSketchMerge", "name" => "visitors", "fieldName" => "visitors"},
                 %{"type" => "doubleMax", "name" => "slowest", "fieldName" => "latency"},
                 %{"type" => "doubleMean", "name" => "mean_latency", "fieldName" => "latency"},
                 %{"type" => "stringFirst", "name" => "first_user", "fieldName" => "user"},
                 %{"type" => "longMin", "name" => "least_added", "fieldName" => "added"}
               ],
               "extraField" => true
             }
    end

    test "a projection without a granularity doesn't group by time" do
      [{module, _}] =
        compile_schema("""
        dimension :channel, :string
        projection :by_channel, group_by: [:channel], aggregate: [edits: :count]
        """)

      assert [projection] = Spec.projections(module)
      refute Map.has_key?(projection, "virtualColumns")
      assert projection["groupingColumns"] == [%{"type" => "string", "name" => "channel"}]
    end

    test "data_schema/2 includes them, and leaves them out without any" do
      assert Spec.data_schema(Edits)["projections"] == Spec.projections(Edits)
      refute Map.has_key?(Spec.data_schema(PageViews), "projections")
      assert Spec.projections(PageViews) == []
    end

    test "the template helper renders them as JSON" do
      assert Edits
             |> Druid.Supervisors.Template.Helpers.projections()
             |> Jason.decode!() == Spec.projections(Edits)
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

    test "projections that don't fit the schema" do
      base = "dimension :channel, :string\nmetric :views, :integer, aggregate: :count\n"

      for {projection, message} <- [
            {"projection :p, group_by: [:nope], aggregate: [n: :count]",
             ~r/projection :p can't group by :nope: not a dimension/},
            {"projection :p, group_by: [:views], aggregate: [n: :count]",
             ~r/can't group by :views: not a dimension/},
            {"projection :p, aggregate: [n: {:sum, :nope}]",
             ~r/can't aggregate :nope: no such column/},
            {"projection :p, aggregate: [n: {:sum, :channel}]",
             ~r/can't aggregate :channel with :sum/},
            {"projection :p, granularity: :fortnight, aggregate: [n: :count]",
             ~r/unknown :granularity :fortnight/},
            {"projection :p, group_by: [:channel]", ~r/needs at least one aggregation/},
            {"projection :p, aggregate: [n: :total]", ~r/unknown aggregation n: :total/}
          ] do
        assert_raise ArgumentError, message, fn -> compile(base <> projection) end
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
