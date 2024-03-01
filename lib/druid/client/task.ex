defmodule Druid.Client.Task do
  @tasks_path "/druid/indexer/v1/tasks"
  @spec all() :: Req.t()
  def all do
    Req.new(method: :get, url: @tasks_path)
  end

  @task_status_path "/druid/indexer/v1/task/:task_id/status"
  @spec status(String.t()) :: Req.t()
  def status(task_id) do
    Req.new(method: :get, url: @task_status_path, path_params: [task_id: task_id])
  end
end
