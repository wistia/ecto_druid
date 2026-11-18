defmodule Druid.Poll do
  @moduledoc false
  # Polling with a deadline, shared by the functions that wait on Druid:
  # Druid.Tasks.await/3, Druid.Supervisors.await_running/3 and handoff/3, and
  # Druid.Lookups.await/3.

  @doc "Returns the deadline for a timeout in milliseconds, or `:infinity`."
  def deadline(:infinity), do: :infinity
  def deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  @doc "Returns the milliseconds left before `deadline`, never less than 0."
  def remaining(:infinity), do: :infinity
  def remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  @doc """
  Calls `check` until it returns `{:done, value}` or `{:error, error}`, sleeping
  `interval` milliseconds after each `:wait` or `{:wait, last}`.

  Returns `{:ok, value}`, `{:error, error}`, or `{:timeout, last}` past the
  deadline, where `last` is what the final `{:wait, last}` carried (`nil` for
  a bare `:wait`).
  """
  def poll(deadline, interval, check) do
    case check.() do
      {:done, value} -> {:ok, value}
      {:error, error} -> {:error, error}
      :wait -> wait(deadline, interval, check, nil)
      {:wait, last} -> wait(deadline, interval, check, last)
    end
  end

  defp wait(deadline, interval, check, last) do
    case remaining(deadline) do
      0 ->
        {:timeout, last}

      remaining ->
        Process.sleep(min(interval, remaining))
        poll(deadline, interval, check)
    end
  end
end
