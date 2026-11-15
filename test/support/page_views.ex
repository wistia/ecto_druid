defmodule Ecto.Adapters.Druid.PageViews do
  use Ecto.Druid.Schema

  @primary_key false
  schema "ecto_druid_page_views_test" do
    timestamp :time, column: "ts", format: "millis"

    dimension :country, :string
    dimension :browser, :string, source: :browser_name
    dimension :tags, {:array, :string}, multi_value: true
    dimension :duration_ms, :integer
    dimension :attributes, :map, druid_type: "auto"
    dimension :visitor_key, :string, from: "user_key"
    dimension :user_agent, :string, from: "user-agent"
    dimension :referrer, :string, from: "referrer"

    metric :views, :integer, aggregate: :count
    metric :watch_time, :float, aggregate: :sum, from: "watch_seconds"
    metric :max_duration, :integer, aggregate: :max, from: "duration_ms"
    metric :sessions, Ecto.Druid.ThetaSketch, from: "session_id", size: 8192
    metric :visitors, Ecto.Druid.HLLSketch, from: "visitor_id", lg_k: 12
    metric :load_times, Ecto.Druid.QuantilesSketch, from: "load_ms", k: 128

    metric :scroll_depth, :map,
      aggregate: "fixedBucketsHistogram",
      from: "scroll_pct",
      lower_limit: 0,
      upper_limit: 100,
      num_buckets: 10,
      outlier_handling_mode: "overflow"

    # Queryable, but not part of the ingestion spec
    field :page_title, :string
  end
end
