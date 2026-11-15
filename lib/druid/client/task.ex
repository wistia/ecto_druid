defmodule Druid.Client.Task do
  @moduledoc """
  Builds requests for Druid's [tasks API](https://druid.apache.org/docs/latest/api-reference/tasks-api).

  The tasks API is served by the Overlord, so send these requests to the
  Router or Overlord rather than a Broker.
  """

  import Druid.Client.Util

  @indexer_path "/druid/indexer/v1"
  @task_path @indexer_path <> "/task"

  @filters [
    state: "state",
    datasource: "datasource",
    created_time_interval: "createdTimeInterval",
    max: "max",
    type: "type"
  ]

  @doc """
  Builds a request to list tasks, newest first.

  ## Options

    * `:state` - Only tasks in this state: `"running"`, `"complete"`,
      `"waiting"`, or `"pending"`.
    * `:datasource` - Only tasks for this data source.
    * `:created_time_interval` - Only tasks created within this ISO 8601
      interval, such as `"2024-01-01/2024-01-02"`.
    * `:max` - Return at most this many complete tasks.
    * `:type` - Only tasks of this type, such as `"index_parallel"`.

  ## Examples

      Druid.Client.Task.all()
      |> Druid.Client.request!(host: "localhost", port: 8888)

      Druid.Client.Task.all(state: "running", datasource: "wikipedia")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec all(Keyword.t()) :: Req.Request.t()
  def all(opts \\ []) do
    Req.new(method: :get, url: @indexer_path <> "/tasks", params: filter_params(opts))
  end

  @doc """
  Builds a request to list complete tasks. Takes the same options as `all/1`.
  """
  @spec complete(Keyword.t()) :: Req.Request.t()
  def complete(opts \\ []), do: list("completeTasks", opts)

  @doc """
  Builds a request to list running tasks. Takes the same options as `all/1`.
  """
  @spec running(Keyword.t()) :: Req.Request.t()
  def running(opts \\ []), do: list("runningTasks", opts)

  @doc """
  Builds a request to list tasks waiting on a lock. Takes the same options as
  `all/1`.
  """
  @spec waiting(Keyword.t()) :: Req.Request.t()
  def waiting(opts \\ []), do: list("waitingTasks", opts)

  @doc """
  Builds a request to list tasks waiting for a worker. Takes the same options
  as `all/1`.
  """
  @spec pending(Keyword.t()) :: Req.Request.t()
  def pending(opts \\ []), do: list("pendingTasks", opts)

  @doc """
  Builds a request to get a task's status by ID.

  ## Examples

      Druid.Client.Task.status("123")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec status(String.t()) :: Req.Request.t()
  def status(task_id) do
    Req.new(method: :get, url: path(@task_path, [task_id, "status"]))
  end

  @doc """
  Builds a request to get the statuses of several tasks, as a map of task ID
  to status. Unknown IDs are left out.
  """
  @spec statuses([String.t()]) :: Req.Request.t()
  def statuses(task_ids) do
    Req.new(method: :post, url: @indexer_path <> "/taskStatus", json: task_ids)
  end

  @doc """
  Builds a request to get a task's payload (its spec) by ID.

  ## Examples

      Druid.Client.Task.result("123")
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec result(String.t()) :: Req.Request.t()
  def result(task_id) do
    Req.new(method: :get, url: path(@task_path, [task_id]))
  end

  @doc """
  Builds a request to get a task's completion report, which includes row
  counts, errors, and for SQL-based ingestion the query's stage details.
  """
  @spec reports(String.t()) :: Req.Request.t()
  def reports(task_id) do
    Req.new(method: :get, url: path(@task_path, [task_id, "reports"]))
  end

  @doc """
  Builds a request to get a task's log as text.

  ## Options

    * `:offset` - Start this many bytes into the log. A negative offset
      counts back from the end.
  """
  @spec log(String.t(), Keyword.t()) :: Req.Request.t()
  def log(task_id, opts \\ []) do
    Req.new(
      method: :get,
      url: path(@task_path, [task_id, "log"]),
      params: params(opts, offset: "offset")
    )
  end

  @doc """
  Builds a request to submit a native task, such as an `index_parallel` or
  `kill` task. Druid responds with `%{"task" => task_id}`.

  For batch ingestion with SQL, see `Druid.Client.SQL.insert/3`.

  ## Examples

      Druid.Client.Task.submit(%{"type" => "index_parallel", "spec" => %{...}})
      |> Druid.Client.request!(host: "localhost", port: 8888)
  """
  @spec submit(map()) :: Req.Request.t()
  def submit(task) do
    Req.new(method: :post, url: @task_path, json: task)
  end

  @doc """
  Builds a request to shut down a task. This also cancels SQL-based ingestion
  queries, whose task ID is the query ID.
  """
  @spec shutdown(String.t()) :: Req.Request.t()
  def shutdown(task_id) do
    Req.new(method: :post, url: path(@task_path, [task_id, "shutdown"]))
  end

  @doc """
  Builds a request to shut down every task for a data source.
  """
  @spec shutdown_all(String.t()) :: Req.Request.t()
  def shutdown_all(data_source) do
    Req.new(
      method: :post,
      url: path(@indexer_path <> "/datasources", [data_source, "shutdownAllTasks"])
    )
  end

  @doc """
  Builds a request to delete a data source's pending segments, which are
  allocated to tasks but not yet published. Druid responds with
  `%{"numDeleted" => count}`.
  """
  @spec delete_pending_segments(String.t()) :: Req.Request.t()
  def delete_pending_segments(data_source) do
    Req.new(method: :delete, url: path(@indexer_path <> "/pendingSegments", [data_source]))
  end

  defp list(endpoint, opts) do
    Req.new(method: :get, url: @indexer_path <> "/" <> endpoint, params: filter_params(opts))
  end

  defp filter_params(opts) do
    opts
    |> Keyword.update(:created_time_interval, nil, &path_interval/1)
    |> params(@filters)
  end
end
