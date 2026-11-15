defmodule Ecto.Adapters.DruidTest do
  use ExUnit.Case
  alias Ecto.Adapters.Druid

  describe "checkout/1" do
    test "proxies to fun" do
      assert Druid.checkout(:meta, :opts, fn -> :ok end) == :ok
    end
  end

  describe "checked_out?/1" do
    test "returns false" do
      assert Druid.checked_out?(:meta) == false
    end
  end

  describe "dumpers/2" do
    test "dumps the correct types" do
      assert Druid.dumpers(:string, :string) == [:string]
    end

    test "dumps custom types through the custom type" do
      assert Druid.dumpers(:string, Ecto.Druid.DateTime) == [Ecto.Druid.DateTime]
    end

    # TODO: Add more types
  end

  describe "loaders/2" do
    test "loads the correct types" do
      assert Druid.loaders(:integer, {:maybe, :integer}) == [:integer, {:maybe, :integer}]
    end

    # TODO: Add more types
  end

  describe "Types.to_db/1" do
    alias Ecto.Adapters.Druid.Types

    test "tags params with Avatica SQL types" do
      assert Types.to_db(1) == %{type: "BIGINT", value: 1}
      assert Types.to_db(1.5) == %{type: "DOUBLE", value: 1.5}
      assert Types.to_db("a") == %{type: "VARCHAR", value: "a"}
      assert Types.to_db(true) == %{type: "BOOLEAN", value: true}
    end

    test "sends datetimes as ISO8601 timestamps" do
      assert Types.to_db(~U[2016-06-27 00:00:00Z]) ==
               %{type: "TIMESTAMP", value: "2016-06-27T00:00:00Z"}

      assert Types.to_db(~N[2016-06-27 00:00:00]) ==
               %{type: "TIMESTAMP", value: "2016-06-27T00:00:00"}
    end
  end

  describe "prepare/2" do
    # Integration tested
  end

  describe "merge_context/2" do
    test "uses the repo config context by default" do
      opts = Druid.merge_context([context: %{sqlTimeZone: "America/New_York"}], [])
      assert opts[:context] == %{sqlTimeZone: "America/New_York"}
    end

    test "per-call context overrides repo config context" do
      opts =
        Druid.merge_context(
          [context: %{sqlTimeZone: "America/New_York", timeout: 1000}],
          context: %{sqlTimeZone: "UTC"}
        )

      assert opts[:context] == %{sqlTimeZone: "UTC", timeout: 1000}
    end

    test "defaults to an empty context" do
      assert Druid.merge_context([], [])[:context] == %{}
    end
  end
end
