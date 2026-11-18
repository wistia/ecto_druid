defmodule SketchIntegrationTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  use Ecto.Druid.Query

  alias Ecto.Adapters.Druid.IntegrationRepo

  @druid [host: "localhost", port: 9888]
  @data_source "ecto_druid_sketch_test"

  # SQL-based ingestion runs as a task, which takes a while in the test cluster
  @moduletag timeout: 600_000

  defmodule PageSketches do
    use Ecto.Schema

    @primary_key false
    schema "ecto_druid_sketch_test" do
      field :page, :string
      field :visitors, Ecto.Druid.HLLSketch
      field :sessions, Ecto.Druid.ThetaSketch
      field :added, Ecto.Druid.QuantilesSketch
    end
  end

  setup_all do
    query =
      from w in "wikipedia",
        where: w.page in ["Black Dahlia", "(1094) Siberia"],
        group_by: w.page,
        select: %{
          __time: fragment("TIMESTAMP '2026-01-01'"),
          page: w.page,
          visitors: ds_hll(w.user),
          sessions: ds_theta(w.user),
          added: ds_quantiles_sketch(w.added)
        }

    {2, nil} =
      IntegrationRepo.insert_all(@data_source, query,
        partitioned_by: :all,
        overwrite: :all,
        wait_for_segments: true
      )

    on_exit(fn ->
      Druid.Client.DataSource.mark_unused(@data_source) |> Druid.Client.request(@druid)
    end)

    :ok
  end

  defp black_dahlia do
    IntegrationRepo.one!(from s in PageSketches, where: s.page == "Black Dahlia", select: s)
  end

  test "sketch columns load as Base64 strings" do
    assert %PageSketches{visitors: visitors, sessions: sessions, added: added} = black_dahlia()

    for sketch <- [visitors, sessions, added] do
      assert {:ok, _} = Base.decode64(sketch)
    end
  end

  test "a loaded sketch can be pinned back into a query" do
    %PageSketches{visitors: visitors, sessions: sessions} = black_dahlia()

    query =
      from s in PageSketches,
        where: s.page == "Black Dahlia",
        select: {
          hll_sketch_estimate(decode_base64_complex("HLLSketch", ^visitors)),
          theta_sketch_estimate(
            decode_base64_complex("thetaSketch", type(^sessions, Ecto.Druid.ThetaSketch))
          )
        }

    assert IntegrationRepo.one!(query) == {1.0, 1.0}
  end

  test "aggregations load as Elixir values" do
    query =
      from w in "wikipedia",
        where: w.page in ["Black Dahlia", "(1094) Siberia", "(2383) Bradley"],
        select: %{
          hll: hll_sketch_estimate_with_error_bounds(ds_hll(w.user)),
          theta: theta_sketch_estimate_with_error_bounds(ds_theta(w.user), 1),
          quantiles: ds_get_quantiles(ds_quantiles_sketch(w.added), [0.5, 0.9]),
          histogram: ds_histogram(ds_quantiles_sketch(w.added), [10.0]),
          cdf: ds_cdf(ds_quantiles_sketch(w.added), [10.0]),
          tdigest: tdigest_generate_sketch(w.added)
        }

    assert %{
             hll: %Ecto.Druid.Estimate{lower_bound: 3.0} = hll,
             theta: %Ecto.Druid.Estimate{value: 3.0, lower_bound: 3.0, upper_bound: 3.0},
             quantiles: [3.0, 39.0],
             histogram: [2.0, 1.0],
             cdf: [cdf, 1.0],
             tdigest: tdigest
           } = IntegrationRepo.one!(query)

    assert_in_delta hll.value, 3.0, 0.001
    assert hll.upper_bound > hll.value
    assert_in_delta cdf, 2 / 3, 0.001
    assert {:ok, _} = Base.decode64(tdigest)
  end
end
