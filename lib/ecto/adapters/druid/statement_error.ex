defmodule Ecto.Adapters.Druid.StatementError do
  @moduledoc """
  Raised when a query from deep storage fails, is canceled, or runs past its
  `:timeout`.

  `:query_id` is the statement's id in Druid, `:state` its last known state,
  and `:details` Druid's `errorDetails`, such as `"errorCode"` and
  `"errorMessage"`, when Druid reported an error.
  """
  defexception [:message, :query_id, :state, :details]

  @impl true
  def exception(%{"queryId" => query_id, "state" => state} = status) do
    details = Map.get(status, "errorDetails")

    reason =
      case details do
        %{"errorCode" => code, "errorMessage" => message} -> " (#{code}): #{message}"
        %{"errorMessage" => message} -> ": #{message}"
        _ -> ""
      end

    %__MODULE__{
      message: "Statement #{query_id} #{String.downcase(state)}#{reason}",
      query_id: query_id,
      state: state,
      details: details
    }
  end

  def exception(opts) when is_list(opts), do: struct!(__MODULE__, opts)
end
