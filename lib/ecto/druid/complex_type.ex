defmodule Ecto.Druid.ComplexType do
  defmacro __using__(_) do
    quote do
      @behaviour Ecto.Type

      def type, do: __MODULE__
      def cast(value), do: value
      def embed_as(_value), do: :self
      def equal?(value1, value2), do: value1 == value2

      # TODO: This seems to get called multiple times, sometimes on the encoded value and sometimes the decoded one
      def load(value) when is_binary(value) do
        with {:error, _} <- Jason.decode(value) do
          {:ok, value}
        end
      end

      def load(value), do: {:ok, value}

      def dump(value) do
        with {:error, _} <- Jason.encode(value) do
          :error
        end
      end

      defoverridable Ecto.Type
    end
  end
end
