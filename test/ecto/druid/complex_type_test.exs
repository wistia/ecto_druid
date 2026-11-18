defmodule Ecto.Druid.ComplexTypeTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Druid

  alias Ecto.Druid.{
    DSHistogram,
    Estimate,
    HLLSketch,
    QuantilesSketch,
    TDigestSketch,
    ThetaSketch,
    TupleSketch
  }

  @sketch "AgEHDAMIAQAiw2QM"

  defmodule Row do
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :visitors, Ecto.Druid.HLLSketch
      field :histogram, Ecto.Druid.DSHistogram
    end
  end

  for type <- [HLLSketch, ThetaSketch, QuantilesSketch, TupleSketch, TDigestSketch] do
    describe inspect(type) do
      test "casts and dumps Base64 strings" do
        assert Ecto.Type.cast(unquote(type), @sketch) == {:ok, @sketch}
        assert Ecto.Type.cast(unquote(type), 1) == :error
        assert Ecto.Type.cast({:array, unquote(type)}, [@sketch]) == {:ok, [@sketch]}
        assert Ecto.Type.adapter_dump(Druid, unquote(type), @sketch) == {:ok, @sketch}
      end

      test "loads JSON-encoded and bare Base64 strings" do
        assert Ecto.Type.adapter_load(Druid, unquote(type), ~s("#{@sketch}")) == {:ok, @sketch}
        assert Ecto.Type.adapter_load(Druid, unquote(type), @sketch) == {:ok, @sketch}
        assert Ecto.Type.adapter_load(Druid, unquote(type), nil) == {:ok, nil}
        assert Ecto.Type.adapter_load(Druid, unquote(type), ~s("not closed)) == :error
      end
    end
  end

  describe "DSHistogram" do
    test "casts, loads and dumps arrays of doubles" do
      assert Ecto.Type.cast(DSHistogram, [0, 1.5]) == {:ok, [0.0, 1.5]}
      assert Ecto.Type.cast(DSHistogram, "[0]") == :error
      assert Ecto.Type.adapter_load(Druid, DSHistogram, "[0,1.0]") == {:ok, [0.0, 1.0]}
      assert Ecto.Type.adapter_load(Druid, DSHistogram, [0, 1.0]) == {:ok, [0.0, 1.0]}
      assert Ecto.Type.adapter_load(Druid, DSHistogram, "[") == :error
      assert Ecto.Type.adapter_dump(Druid, DSHistogram, [1.0]) == {:ok, [1.0]}
    end
  end

  describe "Estimate" do
    @estimate %Estimate{value: 3.0, lower_bound: 2.0, upper_bound: 4.5}

    test "loads HLL's array" do
      assert Ecto.Type.adapter_load(Druid, Estimate, [3, 2.0, 4.5]) == {:ok, @estimate}
      assert Ecto.Type.adapter_load(Druid, Estimate, "[3,2.0,4.5]") == {:ok, @estimate}
    end

    test "loads theta's JSON object" do
      json = ~s({"estimate":3,"highBound":4.5,"lowBound":2.0,"numStdDev":1})
      assert Ecto.Type.adapter_load(Druid, Estimate, json) == {:ok, @estimate}
    end

    test "rejects other values" do
      assert Ecto.Type.adapter_load(Druid, Estimate, [1.0]) == :error
      assert Ecto.Type.adapter_load(Druid, Estimate, ~s({"estimate":1})) == :error
      assert Ecto.Type.adapter_load(Druid, Estimate, "3.0") == :error
      assert Ecto.Type.adapter_load(Druid, Estimate, nil) == {:ok, nil}
    end

    test "casts only an estimate" do
      assert Ecto.Type.cast(Estimate, @estimate) == {:ok, @estimate}
      assert Ecto.Type.cast(Estimate, [3.0, 2.0, 4.5]) == :error
    end
  end

  test "sketch fields cast in a changeset" do
    changeset =
      Ecto.Changeset.cast(%Row{}, %{visitors: @sketch, histogram: [1, 2]}, [:visitors, :histogram])

    assert changeset.valid?
    assert changeset.changes == %{visitors: @sketch, histogram: [1.0, 2.0]}

    refute Ecto.Changeset.cast(%Row{}, %{visitors: 1}, [:visitors]).valid?
  end
end
