defmodule Druid.Client.Supervisor do
  @moduledoc """
  Builds requests for Druid's [supervisor API](https://druid.apache.org/docs/latest/api-reference/supervisor-api).

  Supervisors manage streaming ingestion (for example `kafka`) and automatic
  compaction (`autocompact`). The supervisor API is served by the Overlord, so
  send these requests to the Router or Overlord rather than a Broker.

  To manage supervisor specs from templates, see `Druid.Supervisors`.
  """

  @supervisors_path "/druid/indexer/v1/supervisor"

  @doc """
  Builds a request to list the IDs of all active supervisors.

  ## Examples

      Druid.Client.Supervisor.list()
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec list() :: Req.Request.t()
  def list do
    Req.new(method: :get, url: @supervisors_path)
  end

  @doc """
  Builds a request to get the spec of a supervisor.

  ## Examples

      Druid.Client.Supervisor.get("wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec get(String.t()) :: Req.Request.t()
  def get(id) do
    Req.new(method: :get, url: supervisor_path(id))
  end

  @doc """
  Builds a request to get the status report of a supervisor.

  ## Examples

      Druid.Client.Supervisor.status("wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec status(String.t()) :: Req.Request.t()
  def status(id) do
    Req.new(method: :get, url: supervisor_path(id, "status"))
  end

  @doc """
  Builds a request to create a supervisor, or update it if one with the same ID
  exists.

  Druid responds with `%{"id" => id, "modified" => boolean, "restarted" => boolean}`.

  ## Options

  * `:skip_restart_if_unmodified` - When `true` (the default), Druid leaves a
    running supervisor alone if the submitted spec matches the current one.
    When `false`, Druid always restarts the supervisor's tasks.

  ## Examples

      Druid.Client.Supervisor.submit(%{"type" => "kafka", "spec" => %{...}})
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec submit(map(), Keyword.t()) :: Req.Request.t()
  def submit(spec, opts \\ []) do
    skip_restart = Keyword.get(opts, :skip_restart_if_unmodified, true)

    Req.new(
      method: :post,
      url: @supervisors_path,
      params: [skipRestartIfUnmodified: skip_restart],
      json: spec
    )
  end

  @doc """
  Builds a request to suspend a supervisor.
  """
  @spec suspend(String.t()) :: Req.Request.t()
  def suspend(id), do: action(id, "suspend")

  @doc """
  Builds a request to resume a suspended supervisor.
  """
  @spec resume(String.t()) :: Req.Request.t()
  def resume(id), do: action(id, "resume")

  @doc """
  Builds a request to reset a supervisor's stored offsets. Druid then reads
  from the earliest or latest offset, depending on `useEarliestOffset`.
  """
  @spec reset(String.t()) :: Req.Request.t()
  def reset(id), do: action(id, "reset")

  @doc """
  Builds a request to terminate a supervisor. Its running tasks stop and
  publish their segments.
  """
  @spec terminate(String.t()) :: Req.Request.t()
  def terminate(id), do: action(id, "terminate")

  defp action(id, action) do
    Req.new(method: :post, url: supervisor_path(id, action))
  end

  # Req's path_params leave "/" unescaped, so escape the ID ourselves.
  defp supervisor_path(id, suffix \\ nil) do
    path = @supervisors_path <> "/" <> URI.encode(id, &URI.char_unreserved?/1)
    if suffix, do: path <> "/" <> suffix, else: path
  end
end
