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
      assert Druid.dumpers(:string, :string) == [:string, :string]
    end

    # TODO: Add more types
  end

  describe "loaders/2" do
    test "loads the correct types" do
      assert Druid.loaders(:integer, {:maybe, :integer}) == [:integer, {:maybe, :integer}]
    end

    # TODO: Add more types
  end

  describe "prepare/2" do
    # Integration tested
  end
end
