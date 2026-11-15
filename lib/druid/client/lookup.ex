defmodule Druid.Client.Lookup do
  @moduledoc """
  Builds requests for Druid's [lookups API](https://druid.apache.org/docs/latest/api-reference/lookups-api).

  Lookups are configured per tier (`"__default"` unless you run several).
  The API is served by the Coordinator, so send these requests to the Router
  or Coordinator rather than a Broker.

  Each lookup is stored as `%{"version" => version, "lookupExtractorFactory"
  => factory}`. Druid only replaces a lookup when the new version sorts after
  the current one as a string.

  To manage lookups from templates, see `Druid.Lookups`.
  """

  @config_path "/druid/coordinator/v1/lookups/config"

  @doc """
  Builds a request to get every lookup, as a map of tier to lookup name to
  lookup.

  Druid responds with a 404 until lookups are initialized. See
  `initialize/0`.

  ## Examples

      Druid.Client.Lookup.all()
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec all() :: Req.Request.t()
  def all do
    Req.new(method: :get, url: @config_path <> "/all")
  end

  @doc """
  Builds a request to get one lookup.
  """
  @spec get(String.t(), String.t()) :: Req.Request.t()
  def get(tier, name) do
    Req.new(method: :get, url: lookup_path(tier, name))
  end

  @doc """
  Builds a request to create or replace one lookup.

  `factory` is the lookup's `lookupExtractorFactory`, for example
  `%{"type" => "map", "map" => %{"a" => "b"}}`. `version` must sort after the
  lookup's current version, or Druid rejects the update.
  """
  @spec set(String.t(), String.t(), String.t(), map()) :: Req.Request.t()
  def set(tier, name, version, factory) do
    Req.new(
      method: :post,
      url: lookup_path(tier, name),
      json: %{"version" => version, "lookupExtractorFactory" => factory}
    )
  end

  @doc """
  Builds a request to create or replace several lookups at once, given as a
  map of tier to lookup name to lookup.

  Posting an empty map initializes lookups on a cluster that has none yet.
  """
  @spec update(map()) :: Req.Request.t()
  def update(lookups) do
    Req.new(method: :post, url: @config_path, json: lookups)
  end

  @doc """
  Builds a request to initialize lookups on a cluster that has none yet.
  Druid rejects lookup changes until this is done.
  """
  @spec initialize() :: Req.Request.t()
  def initialize, do: update(%{})

  @doc """
  Builds a request to delete one lookup.
  """
  @spec delete(String.t(), String.t()) :: Req.Request.t()
  def delete(tier, name) do
    Req.new(method: :delete, url: lookup_path(tier, name))
  end

  @doc """
  Builds a request to get whether a lookup is loaded on every node of its
  tier.
  """
  @spec status(String.t(), String.t()) :: Req.Request.t()
  def status(tier, name) do
    Req.new(
      method: :get,
      url: "/druid/coordinator/v1/lookups/status/" <> escape(tier) <> "/" <> escape(name)
    )
  end

  defp lookup_path(tier, name), do: @config_path <> "/" <> escape(tier) <> "/" <> escape(name)

  defp escape(segment), do: URI.encode(segment, &URI.char_unreserved?/1)
end
