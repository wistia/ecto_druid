defmodule Ecto.Druid.ComplexType do
  @moduledoc """
  Can be used to define a default implementation for a Druid complex type that implements the Ecto.Type behavior.
  Any Ecto.Type behavior can be overridden by defining the corresponding function in the module that uses this macro.

  ## Example

      defmodule MyType do
        use Ecto.Druid.ComplexType
      end
  """

  @doc false
  defmacro __using__(_) do
    quote do
      @type_name __MODULE__ |> Module.split() |> List.last()
      @moduledoc """
      An Ecto.Type for encoding/decoding #{@type_name} values.
      """
      @behaviour Ecto.Type

      # Elixir type database returns
      @impl Ecto.Type
      def type, do: :complex
      @impl Ecto.Type
      def cast(value), do: value
      @impl Ecto.Type
      def embed_as(_value), do: :self
      @impl Ecto.Type
      def equal?(value1, value2), do: value1 == value2

      @impl Ecto.Type
      def load(value) when is_binary(value) do
        with {:error, _} <- Jason.decode(value) do
          :error
        end
      end

      def load(_value), do: :error

      @impl Ecto.Type
      def dump(value) do
        with {:error, _} <- Jason.encode(value) do
          :error
        end
      end

      defoverridable Ecto.Type
    end
  end
end
