defmodule Druid.Client.Util do
  @moduledoc false

  # Req's path_params leave "/" unescaped, so path segments are escaped here.
  @spec path(String.t(), [String.t()]) :: String.t()
  def path(base, segments) do
    Enum.reduce(segments, base, fn segment, acc -> acc <> "/" <> escape(segment) end)
  end

  @spec escape(String.t()) :: String.t()
  def escape(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  # Druid's path intervals use "_" in place of the ISO 8601 "/" separator.
  @spec path_interval(Druid.Interval.t() | String.t()) :: String.t()
  def path_interval(interval),
    do: interval |> Druid.Interval.to_iso8601() |> String.replace("/", "_")

  @doc """
  Turns `opts` into query params using `mapping` of option to param name.
  Options that are missing, `nil`, or `false` are dropped, since Druid treats
  many params as flags that are on whenever present.
  """
  @spec params(Keyword.t(), Keyword.t()) :: [{String.t(), term}]
  def params(opts, mapping) do
    for {key, param} <- mapping,
        value = Keyword.get(opts, key),
        value not in [nil, false],
        do: {param, value}
  end

  @doc """
  Builds the headers Druid records in a config change's audit history.
  """
  @spec audit_headers(Keyword.t()) :: [{String.t(), String.t()}]
  def audit_headers(opts) do
    for {key, header} <- [author: "x-druid-author", comment: "x-druid-comment"],
        value = Keyword.get(opts, key),
        value != nil,
        do: {header, value}
  end
end
