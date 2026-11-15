defmodule Druid.Client.Supervisor do
  @moduledoc """
  Builds requests for Druid's [supervisor API](https://druid.apache.org/docs/latest/api-reference/supervisor-api).

  Supervisors manage streaming ingestion (for example `kafka`) and automatic
  compaction (`autocompact`). The supervisor API is served by the Overlord, so
  send these requests to the Router or Overlord rather than a Broker.

  To manage supervisor specs from templates, see `Druid.Supervisors`.
  """

  import Druid.Client.Util, only: [escape: 1, params: 2]

  @supervisors_path "/druid/indexer/v1/supervisor"

  @doc """
  Builds a request to list the IDs of all active supervisors.

  ## Options

    * `:full` - When `true`, list each supervisor's spec and state rather
      than only its ID.
    * `:state` - When `true`, list each supervisor's state, including whether
      it is suspended and healthy.

  ## Examples

      Druid.Client.Supervisor.list()
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.Supervisor.list(state: true)
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec list(Keyword.t()) :: Req.Request.t()
  def list(opts \\ []) do
    Req.new(
      method: :get,
      url: @supervisors_path,
      params: params(opts, full: "full", state: "state")
    )
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
  Builds a request to get a supervisor's health. Druid responds with a 200
  when it is healthy and a 503 when it is not, so `Druid.Client.request/2`
  returns an error for an unhealthy supervisor.
  """
  @spec health(String.t()) :: Req.Request.t()
  def health(id) do
    Req.new(method: :get, url: supervisor_path(id, "health"))
  end

  @doc """
  Builds a request to get a supervisor's row statistics, such as rows
  processed and thrown away, per task group and task.
  """
  @spec stats(String.t()) :: Req.Request.t()
  def stats(id) do
    Req.new(method: :get, url: supervisor_path(id, "stats"))
  end

  @doc """
  Builds a request to get the spec history of every supervisor, as a map of
  supervisor ID to versions, newest first.
  """
  @spec history() :: Req.Request.t()
  def history do
    Req.new(method: :get, url: @supervisors_path <> "/history")
  end

  @doc """
  Builds a request to get the spec history of a supervisor, newest first.

  ## Options

    * `:count` - Return at most this many versions.
  """
  @spec history(String.t(), Keyword.t()) :: Req.Request.t()
  def history(id, opts \\ []) do
    Req.new(
      method: :get,
      url: supervisor_path(id, "history"),
      params: params(opts, count: "count")
    )
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

  @doc """
  Builds a request to reset a supervisor's stored offsets for some
  partitions, leaving the others alone.

  `offsets` names the stream type and the offsets to resume from, for example:

      %{
        "type" => "kafka",
        "partitions" => %{
          "type" => "end",
          "stream" => "wikipedia",
          "partitionOffsetMap" => %{"0" => 100, "1" => 200}
        }
      }
  """
  @spec reset_offsets(String.t(), map()) :: Req.Request.t()
  def reset_offsets(id, offsets) do
    Req.new(method: :post, url: supervisor_path(id, "resetOffsets"), json: offsets)
  end

  @doc """
  Builds a request to have some of a supervisor's task groups stop reading
  and publish their segments early. New tasks then take over.
  """
  @spec handoff(String.t(), [non_neg_integer()]) :: Req.Request.t()
  def handoff(id, task_group_ids) do
    Req.new(
      method: :post,
      url: supervisor_path(id, "taskGroups/handoff"),
      json: %{"taskGroupIds" => task_group_ids}
    )
  end

  @doc """
  Builds a request to suspend every supervisor.
  """
  @spec suspend_all() :: Req.Request.t()
  def suspend_all, do: Req.new(method: :post, url: @supervisors_path <> "/suspendAll")

  @doc """
  Builds a request to resume every suspended supervisor.
  """
  @spec resume_all() :: Req.Request.t()
  def resume_all, do: Req.new(method: :post, url: @supervisors_path <> "/resumeAll")

  @doc """
  Builds a request to terminate every supervisor.
  """
  @spec terminate_all() :: Req.Request.t()
  def terminate_all, do: Req.new(method: :post, url: @supervisors_path <> "/terminateAll")

  defp action(id, action) do
    Req.new(method: :post, url: supervisor_path(id, action))
  end

  defp supervisor_path(id, suffix \\ nil) do
    path = @supervisors_path <> "/" <> escape(id)
    if suffix, do: path <> "/" <> suffix, else: path
  end
end
