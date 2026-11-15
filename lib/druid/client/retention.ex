defmodule Druid.Client.Retention do
  @moduledoc """
  Builds requests for Druid's [retention rules API](https://druid.apache.org/docs/latest/api-reference/retention-rules-api).

  Retention rules decide which segments the Historicals load, and on which
  tiers. The API is served by the Coordinator, so send these requests to the
  Router or Coordinator rather than a Broker.

  The rules for the cluster-wide default live under the data source name
  `"_default"`.

  To manage retention rules from templates, see `Druid.Retention`.
  """

  @rules_path "/druid/coordinator/v1/rules"

  @doc """
  Builds a request to get the rules of every data source that has some, plus
  the cluster default under `"_default"`.

  ## Examples

      Druid.Client.Retention.all()
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec all() :: Req.Request.t()
  def all do
    Req.new(method: :get, url: @rules_path)
  end

  @doc """
  Builds a request to get the rules of a data source.
  """
  @spec get(String.t()) :: Req.Request.t()
  def get(data_source) do
    Req.new(method: :get, url: rules_path(data_source))
  end

  @doc """
  Builds a request to replace the rules of a data source. An empty list
  removes them, so the data source falls back to the cluster default.

  ## Options

    * `:author` - Recorded in the rule's audit history.
    * `:comment` - Recorded in the rule's audit history.

  ## Examples

      Druid.Client.Retention.set("wikipedia", [%{"type" => "loadForever"}], comment: "keep it all")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec set(String.t(), [map()], Keyword.t()) :: Req.Request.t()
  def set(data_source, rules, opts \\ []) do
    Req.new(
      method: :post,
      url: rules_path(data_source),
      headers: audit_headers(opts),
      json: rules
    )
  end

  @doc """
  Builds a request to get the audit history of a data source's rules.

  ## Options

    * `:count` - Return at most this many entries.
    * `:interval` - Return entries within this ISO 8601 interval.
  """
  @spec history(String.t(), Keyword.t()) :: Req.Request.t()
  def history(data_source, opts \\ []) do
    Req.new(
      method: :get,
      url: rules_path(data_source) <> "/history",
      params: Keyword.take(opts, [:count, :interval])
    )
  end

  @doc """
  Builds a request to list the tiers that currently have Historicals.
  """
  @spec tiers() :: Req.Request.t()
  def tiers do
    Req.new(method: :get, url: "/druid/coordinator/v1/tiers")
  end

  defp audit_headers(opts) do
    Enum.flat_map([author: "x-druid-author", comment: "x-druid-comment"], fn {key, header} ->
      case Keyword.get(opts, key) do
        nil -> []
        value -> [{header, value}]
      end
    end)
  end

  defp rules_path(data_source) do
    @rules_path <> "/" <> URI.encode(data_source, &URI.char_unreserved?/1)
  end
end
