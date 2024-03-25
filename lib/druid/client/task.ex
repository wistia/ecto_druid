defmodule Druid.Client.Task do
  @moduledoc """
  Builds requests for Druid's task API.
  """

  @doc """
  Builds a request to get all tasks.

  ## Examples

      Druid.Client.Task.all()
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @tasks_path "/druid/indexer/v1/tasks"
  @spec all() :: Req.Request.t()
  def all do
    Req.new(method: :get, url: @tasks_path)
  end

  @doc """
  Builds a request to get a task by ID.

  ## Examples

      Druid.Client.Task.get("123")
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @task_status_path "/druid/indexer/v1/task/:task_id/status"
  @spec status(String.t()) :: Req.Request.t()
  def status(task_id) do
    Req.new(method: :get, url: @task_status_path, path_params: [task_id: task_id])
  end

  @doc """
  Builds a request to get a task result by ID.

  ## Examples

      Druid.Client.Task.result("123")
      |> Druid.Client.request!(host: "localhost", port: 8082)
  """
  @task_result_path "/druid/indexer/v1/task/:task_id"
  @spec result(String.t()) :: Req.Request.t()
  def result(task_id) do
    Req.new(method: :get, url: @task_result_path, path_params: [task_id: task_id])
  end
end
