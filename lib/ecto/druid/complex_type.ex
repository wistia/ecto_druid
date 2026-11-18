defmodule Ecto.Druid.ComplexType do
  @moduledoc """
  Defines an `Ecto.Type` for a Druid complex type, such as a sketch.

  Druid returns a complex value as a JSON-encoded Base64 string, such as
  `"\\"AgEHDAMIAQAiw2QM\\""`, which loads as the Base64 string. The type also
  casts and dumps Base64 strings, and loads one that isn't JSON-encoded as is.

  Override any `Ecto.Type` callback by defining it in the module that uses
  this macro.

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
      An `Ecto.Type` for #{@type_name} values, which load as Base64 strings.

      A pinned value is sent as a string. Decode it in the query with
      `Ecto.Druid.Query.Scalar.decode_base64_complex/2` to pass it where Druid
      expects a sketch.
      """
      @behaviour Ecto.Type

      @impl Ecto.Type
      def type, do: :complex

      @impl Ecto.Type
      def cast(value), do: Ecto.Druid.ComplexType.cast(value)

      @impl Ecto.Type
      def embed_as(_format), do: :self

      @impl Ecto.Type
      def equal?(value1, value2), do: value1 == value2

      @impl Ecto.Type
      def load(value), do: Ecto.Druid.ComplexType.load(value)

      @impl Ecto.Type
      def dump(value), do: Ecto.Druid.ComplexType.cast(value)

      defoverridable Ecto.Type
    end
  end

  @doc false
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_value), do: :error

  # Druid's results are JSON-encoded. Base64 never starts with a quote, so
  # anything else, such as a value given to Repo.load/2, is already bare.
  @doc false
  def load(<<?", _::binary>> = value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_binary(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  def load(value) when is_binary(value), do: {:ok, value}
  def load(_value), do: :error
end
