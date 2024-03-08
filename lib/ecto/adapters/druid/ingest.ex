defmodule Ecto.Adapters.Druid.Ingest do
  def insert_all(
        adapter_meta,
        schema_meta,
        header,
        rows,
        on_conflict,
        returning,
        placeholders,
        opts
      ) do
    %{source: source, prefix: prefix} = schema_meta
    {_, conflict_params, _} = on_conflict

    {rows, params} =
      case rows do
        {%Ecto.Query{} = query, params} -> {query, Enum.reverse(params)}
        rows -> unzip_inserts(header, rows)
      end

    sql =
      Ecto.Adapters.Druid.Query.insert(
        prefix,
        source,
        header,
        rows,
        on_conflict,
        returning,
        placeholders
      )
      |> IO.iodata_to_binary()

    opts =
      if is_nil(Keyword.get(opts, :cache_statement)) do
        [{:cache_statement, "ecto_insert_all_#{source}"} | opts]
      else
        opts
      end

    params =
      (placeholders ++ Enum.reverse(params, conflict_params))
      |> Enum.map(&Ecto.Adapters.Druid.Types.to_db/1)

    result =
      Druid.Client.SQL.insert(sql, params, opts)
      |> Druid.Client.request!(Keyword.merge(adapter_meta.config, opts))

    # %{num_rows: num, rows: rows} = query!(adapter_meta, sql, all_params, [source: source] ++ opts)
    {1, [%{task_id: result["taskId"], state: result["state"]}]}
  end

  defp unzip_inserts(header, rows) do
    Enum.map_reduce(rows, [], fn fields, params ->
      Enum.map_reduce(header, params, fn key, acc ->
        case :lists.keyfind(key, 1, fields) do
          {^key, {%Ecto.Query{} = query, query_params}} ->
            {{query, length(query_params)}, Enum.reverse(query_params, acc)}

          {^key, {:placeholder, placeholder_index}} ->
            {{:placeholder, Integer.to_string(placeholder_index)}, acc}

          {^key, value} ->
            {key, [value | acc]}

          false ->
            {nil, acc}
        end
      end)
    end)
  end
end
