defmodule Ecto.Adapters.Druid.NativeQueryError do
  @moduledoc """
  Returned by `native_query/2`, and raised by `native_query!/2`, when a
  native query fails.

  `:query_id` is the `queryId` the query ran with, to pass to
  `Druid.Client.Native.cancel/1`. `:reason` is the underlying exception,
  such as a `Druid.Client.RequestError` for an error response from Druid or
  a `Req.TransportError` when the request times out. `:canceled` is whether
  the query was canceled after the request timed out.
  """

  defexception [:message, :query_id, :reason, canceled: false]

  @type t :: %__MODULE__{
          message: String.t(),
          query_id: String.t(),
          reason: Exception.t(),
          canceled: boolean()
        }

  @impl true
  def exception(opts) do
    query_id = Keyword.fetch!(opts, :query_id)
    reason = Keyword.fetch!(opts, :reason)
    canceled = Keyword.get(opts, :canceled, false)

    message =
      "native query #{query_id} failed" <>
        if(canceled, do: " and was canceled", else: "") <>
        ": " <> Exception.message(reason)

    %__MODULE__{message: message, query_id: query_id, reason: reason, canceled: canceled}
  end
end
