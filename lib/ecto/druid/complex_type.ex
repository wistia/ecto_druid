defmodule Ecto.Druid.ComplexType do
  defmacro __using__(_) do
    quote do
      @behaviour Ecto.Type

      # Elixir type database returns
      def type, do: :complex
      def cast(value), do: value
      def embed_as(_value), do: :self
      def equal?(value1, value2), do: value1 == value2

      def load(value) when is_binary(value) do
        with {:error, _} <- Jason.decode(value) do
          :error
        end
      end

      def load(_value), do: :error

      def dump(value) do
        with {:error, _} <- Jason.encode(value) do
          :error
        end
      end

      defoverridable Ecto.Type
    end
  end
end
