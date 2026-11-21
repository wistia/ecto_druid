defmodule Ecto.Adapters.Druid.Query do
  @moduledoc false

  @parent_as __MODULE__
  alias Ecto.Query.{BooleanExpr, JoinExpr, QueryExpr, WithExpr, ByExpr}

  def all(query, as_prefix \\ []) do
    sources = create_names(query, as_prefix)

    cte = cte(query, sources)
    from = from(query, sources)
    select = select(query, sources)
    join = join(query, sources)
    where = where(query, sources)
    group_by = group_by(query, sources)
    having = having(query, sources)
    window = window(query, sources)
    combinations = combinations(query, as_prefix)
    order_by = order_by(query, sources)
    limit = limit(query, sources)
    offset = offset(query, sources)
    lock = lock(query, sources)

    [
      cte,
      select,
      from,
      join,
      where,
      group_by,
      having,
      window,
      combinations,
      order_by,
      limit,
      offset | lock
    ]
  end

  # SQL-based ingestion: INSERT INTO, or REPLACE INTO with an :overwrite.
  # Druid doesn't take a target column list, so the rows or query are
  # selected through an alias that names their columns in header order.
  def insert(prefix, table, header, rows, opts) do
    [
      insert_target(quote_table(prefix, table), Keyword.get(opts, :overwrite)),
      " SELECT * FROM ",
      insert_source(rows),
      " AS \"input\"(",
      quote_names(header),
      ?),
      partitioned_by(Keyword.fetch!(opts, :partitioned_by))
      | clustered_by(Keyword.get(opts, :clustered_by, []))
    ]
  end

  # Deleting rows with SQL-based ingestion: Druid can't remove single rows,
  # so the interval's time chunks are rewritten with every row that isn't
  # deleted. The condition is negated with IS NOT TRUE rather than NOT, since
  # NOT keeps neither the rows it matches nor the rows it is NULL for.
  #
  # The interval's bounds are sent as the first four parameters: two for
  # OVERWRITE WHERE and two for the SELECT's time filter.
  def delete_all(query, opts) do
    interval = Keyword.fetch!(opts, :interval)
    {table, name, condition} = delete_parts(query)
    keep = if condition, do: [?(, condition, ") IS NOT TRUE"], else: "FALSE"

    [
      insert_target(table, interval),
      " SELECT * FROM ",
      table,
      " AS ",
      name,
      " WHERE ",
      Enum.intersperse([interval_filter(name, interval) | [keep]] -- [[]], " AND "),
      partitioned_by(Keyword.fetch!(opts, :partitioned_by))
      | clustered_by(Keyword.get(opts, :clustered_by, []))
    ]
  end

  # Counts the rows delete_all/2 removes, taking the interval's bounds as the
  # first two parameters
  def delete_count(query, interval) do
    {table, name, condition} = delete_parts(query)
    match = if condition, do: [?(, condition, ?)], else: []

    case [interval_filter(name, interval), match] -- [[], []] do
      [] ->
        ["SELECT count(*) FROM ", table, " AS ", name]

      filters ->
        [
          "SELECT count(*) FROM ",
          table,
          " AS ",
          name,
          " WHERE " | Enum.intersperse(filters, " AND ")
        ]
    end
  end

  # The quoted table, its alias and the WHERE condition (nil without one)
  defp delete_parts(%{from: %{source: {table, _schema}}} = query) when is_binary(table) do
    sources = create_names(query, [])
    {_expr, name, _schema} = elem(sources, 0)
    condition = if query.wheres != [], do: boolean([], query.wheres, sources, query)
    {quote_table(query.from.prefix || query.prefix, table), name, condition}
  end

  defp delete_parts(query) do
    error!(query, "delete_all needs a data source to delete from, not a subquery or fragment")
  end

  defp interval_filter(_name, :all), do: []

  defp interval_filter(name, _interval),
    do: [name, ~S(."__time" >= ? AND ), name, ~S(."__time" < ?)]

  defp insert_target(table, nil), do: ["INSERT INTO ", table]
  defp insert_target(table, :all), do: ["REPLACE INTO ", table, " OVERWRITE ALL"]

  # The interval's bounds are sent as the first two parameters
  defp insert_target(table, _interval),
    do: ["REPLACE INTO ", table, " OVERWRITE WHERE \"__time\" >= ? AND \"__time\" < ?"]

  defp insert_source(rows) when is_list(rows) do
    [
      "(VALUES ",
      Enum.map_intersperse(rows, ", ", fn row ->
        [?(, Enum.map_intersperse(row, ", ", &insert_value/1), ?)]
      end),
      ?)
    ]
  end

  defp insert_source(%Ecto.Query{} = query), do: [?(, all(query), ?)]

  defp insert_value(nil), do: "NULL"
  defp insert_value({%Ecto.Query{} = query, _params_counter}), do: [?(, all(query), ?)]
  defp insert_value(_), do: ~c"?"

  @granularities ~w(second minute five_minute ten_minute fifteen_minute thirty_minute
                    hour six_hour eight_hour day week month quarter year)a

  defp partitioned_by(:all), do: " PARTITIONED BY ALL TIME"

  defp partitioned_by(granularity) when granularity in @granularities,
    do: [" PARTITIONED BY '", granularity |> Atom.to_string() |> String.upcase(), ?']

  # An ISO 8601 period, such as "PT6H"
  defp partitioned_by("P" <> _ = period), do: [" PARTITIONED BY '", escape_string(period), ?']

  defp partitioned_by(other) do
    raise ArgumentError,
          ":partitioned_by must be :all, one of #{inspect(@granularities)} or an ISO 8601 " <>
            "period such as \"PT6H\", got: #{inspect(other)}"
  end

  defp clustered_by([]), do: []
  defp clustered_by(columns) when is_list(columns), do: [" CLUSTERED BY " | quote_names(columns)]

  defp clustered_by(other) do
    raise ArgumentError, ":clustered_by must be a list of columns, got: #{inspect(other)}"
  end

  ## Query generation

  binary_ops = [
    ==: " = ",
    !=: " != ",
    <=: " <= ",
    >=: " >= ",
    <: " < ",
    >: " > ",
    +: " + ",
    -: " - ",
    *: " * ",
    /: " / ",
    and: " AND ",
    or: " OR ",
    like: " LIKE "
  ]

  @binary_ops Keyword.keys(binary_ops)

  Enum.map(binary_ops, fn {op, str} ->
    defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

  defp select(%{select: %{fields: fields}, distinct: distinct} = query, sources) do
    ["SELECT ", distinct(distinct, sources, query) | select(fields, sources, query)]
  end

  defp distinct(nil, _sources, _query), do: []
  defp distinct(%ByExpr{expr: true}, _sources, _query), do: "DISTINCT "
  defp distinct(%ByExpr{expr: false}, _sources, _query), do: []

  defp distinct(%ByExpr{expr: exprs}, _sources, query) when is_list(exprs) do
    error!(query, "DISTINCT with multiple columns is not supported by Druid")
  end

  defp select([], _sources, _query),
    do: "TRUE"

  defp select(fields, sources, query) do
    Enum.map_intersperse(fields, ", ", fn
      {:&, _, [idx]} ->
        case elem(sources, idx) do
          {nil, source, nil} ->
            error!(
              query,
              "Druid adapter does not support selecting all fields from fragment #{source}. " <>
                "Please specify exactly which fields you want to select"
            )

          {source, _, nil} ->
            error!(
              query,
              "Druid adapter does not support selecting all fields from #{source} without a schema. " <>
                "Please specify a schema or specify exactly which fields you want to select"
            )

          {_, source, _} ->
            source
        end

      {key, value} ->
        [expr(value, sources, query), " AS ", quote_name(key)]

      value ->
        expr(value, sources, query)
    end)
  end

  defp from(%{from: %{source: source, hints: hints}} = query, sources) do
    {from, name} = get_source(query, sources, 0, source)
    [" FROM ", from, " AS ", name | Enum.map(hints, &[?\s | &1])]
  end

  defp cte(%{with_ctes: %WithExpr{queries: [_ | _]}} = query, sources) do
    %{with_ctes: with} = query
    recursive_opt = if with.recursive, do: "RECURSIVE ", else: ""
    ctes = Enum.map_intersperse(with.queries, ", ", &cte_expr(&1, sources, query))
    ["WITH ", recursive_opt, ctes, " "]
  end

  defp cte(%{with_ctes: _}, _), do: []

  defp cte_expr({_name, %{materialized: materialized}, _cte}, _sources, query)
       when is_boolean(materialized) do
    error!(query, "Druid adapter does not support materialized CTEs")
  end

  defp cte_expr({name, opts, cte}, sources, query) do
    operation_opt = Map.get(opts, :operation)

    [quote_name(name), " AS ", cte_query(cte, sources, query, operation_opt)]
  end

  defp cte_query(query, sources, parent_query, nil) do
    cte_query(query, sources, parent_query, :all)
  end

  defp cte_query(%Ecto.Query{} = query, sources, parent_query, :all) do
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    ["(", all(query, subquery_as_prefix(sources)), ")"]
  end

  defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, operation) do
    error!(
      query,
      "Druid adapter does not support data-modifying CTEs (operation: #{operation})"
    )
  end

  defp cte_query(%QueryExpr{expr: expr}, sources, query, _operation) do
    expr(expr, sources, query)
  end

  defp join(%{joins: []}, _sources), do: []

  defp join(%{joins: joins} = query, sources) do
    Enum.map(joins, fn
      %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
        {join, name} = get_source(query, sources, ix, source)

        [
          join_qual(qual, query),
          join,
          " AS ",
          name,
          Enum.map(hints, &[?\s | &1]) | join_on(qual, expr, sources, query)
        ]
    end)
  end

  defp join_on(:cross, true, _sources, _query), do: []
  defp join_on(:cross_lateral, true, _sources, _query), do: []
  defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

  defp join_qual(:inner, _), do: " INNER JOIN "
  defp join_qual(:inner_lateral, _), do: " INNER JOIN LATERAL "
  defp join_qual(:left, _), do: " LEFT OUTER JOIN "
  defp join_qual(:left_lateral, _), do: " LEFT OUTER JOIN LATERAL "
  defp join_qual(:right, _), do: " RIGHT OUTER JOIN "
  defp join_qual(:full, _), do: " FULL OUTER JOIN "
  defp join_qual(:cross, _), do: " CROSS JOIN "
  defp join_qual(:cross_lateral, _), do: " CROSS JOIN LATERAL "

  defp join_qual(qual, query),
    do: error!(query, "join qualifier #{inspect(qual)} is not supported in the Druid adapter")

  defp where(%{wheres: wheres} = query, sources) do
    boolean(" WHERE ", wheres, sources, query)
  end

  defp having(%{havings: havings} = query, sources) do
    boolean(" HAVING ", havings, sources, query)
  end

  defp group_by(%{group_bys: []}, _sources), do: []

  defp group_by(%{group_bys: group_bys} = query, sources) do
    [
      " GROUP BY "
      | Enum.map_intersperse(group_bys, ", ", fn %ByExpr{expr: expr} ->
          Enum.map_intersperse(expr, ", ", &expr(&1, sources, query))
        end)
    ]
  end

  defp window(%{windows: []}, _sources), do: []

  defp window(%{windows: windows} = query, sources) do
    [
      " WINDOW "
      | Enum.map_intersperse(windows, ", ", fn {name, %{expr: kw}} ->
          [quote_name(name), " AS " | window_exprs(kw, sources, query)]
        end)
    ]
  end

  defp window_exprs(kw, sources, query) do
    [?(, Enum.map_intersperse(kw, ?\s, &window_expr(&1, sources, query)), ?)]
  end

  defp window_expr({:partition_by, fields}, sources, query) do
    ["PARTITION BY " | Enum.map_intersperse(fields, ", ", &expr(&1, sources, query))]
  end

  defp window_expr({:order_by, fields}, sources, query) do
    ["ORDER BY " | Enum.map_intersperse(fields, ", ", &order_by_expr(&1, sources, query))]
  end

  defp window_expr({:frame, {:fragment, _, _} = fragment}, sources, query) do
    expr(fragment, sources, query)
  end

  defp order_by(%{order_bys: []}, _sources), do: []

  defp order_by(%{order_bys: order_bys} = query, sources) do
    [
      " ORDER BY "
      | Enum.map_intersperse(order_bys, ", ", fn %{expr: expr} ->
          Enum.map_intersperse(expr, ", ", &order_by_expr(&1, sources, query))
        end)
    ]
  end

  defp order_by_expr({dir, expr}, sources, query) do
    str = expr(expr, sources, query)

    case dir do
      :asc -> str
      :desc -> [str | " DESC"]
      _ -> error!(query, "#{dir} is not supported in ORDER BY in Druid")
    end
  end

  defp limit(%{limit: nil}, _sources), do: []

  defp limit(%{limit: %{with_ties: true}} = query, _sources) do
    error!(query, "Druid adapter does not support the \":with_ties\" limit option")
  end

  defp limit(%{limit: %{expr: expr}} = query, sources) do
    [" LIMIT " | expr(expr, sources, query)]
  end

  defp offset(%{offset: nil}, _sources), do: []

  defp offset(%{offset: %QueryExpr{expr: expr}} = query, sources) do
    [" OFFSET " | expr(expr, sources, query)]
  end

  defp combinations(%{combinations: combinations}, as_prefix) do
    Enum.map(combinations, fn
      {:union, query} -> [" UNION (", all(query, as_prefix), ")"]
      {:union_all, query} -> [" UNION ALL (", all(query, as_prefix), ")"]
      {:except, query} -> [" EXCEPT (", all(query, as_prefix), ")"]
      {:except_all, query} -> [" EXCEPT ALL (", all(query, as_prefix), ")"]
      {:intersect, query} -> [" INTERSECT (", all(query, as_prefix), ")"]
      {:intersect_all, query} -> [" INTERSECT ALL (", all(query, as_prefix), ")"]
    end)
  end

  defp lock(%{lock: nil}, _sources), do: []
  defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [?\s | binary]
  defp lock(%{lock: expr} = query, sources), do: [?\s | expr(expr, sources, query)]

  defp boolean(_name, [], _sources, _query), do: []

  defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
    [
      name,
      Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
        %BooleanExpr{expr: expr, op: op}, {op, acc} ->
          {op, [acc, operator_to_boolean(op) | paren_expr(expr, sources, query)]}

        %BooleanExpr{expr: expr, op: op}, {_, acc} ->
          {op, [?(, acc, ?), operator_to_boolean(op) | paren_expr(expr, sources, query)]}
      end)
      |> elem(1)
    ]
  end

  defp operator_to_boolean(:and), do: " AND "
  defp operator_to_boolean(:or), do: " OR "

  defp parens_for_select([first_expr | _] = expr) do
    if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select/i) do
      [?(, expr, ?)]
    else
      expr
    end
  end

  defp paren_expr(expr, sources, query) do
    [?(, expr(expr, sources, query), ?)]
  end

  defp expr({:^, [], [_ix]}, _sources, _query) do
    ~c"?"
  end

  defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
       when is_atom(field) do
    {ix, sources} = get_parent_sources_ix(query, as)
    {_, name, _} = elem(sources, ix)
    [name, ?. | quote_name(field)]
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
       when is_atom(field) do
    {_, name, _} = elem(sources, idx)
    [name, ?. | quote_name(field)]
  end

  defp expr({:&, _, [idx]}, sources, _query) do
    {_, source, _} = elem(sources, idx)
    source
  end

  defp expr({:in, _, [_left, []]}, _sources, _query) do
    "false"
  end

  defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
    args = Enum.map_intersperse(right, ?,, &expr(&1, sources, query))
    [expr(left, sources, query), " IN (", args, ?)]
  end

  defp expr({:in, _, [_, {:^, _, [_, 0]}]}, _sources, _query) do
    "false"
  end

  defp expr({:in, _, [left, {:^, _, [_, length]}]}, sources, query) do
    args = Enum.intersperse(List.duplicate(??, length), ?,)
    [expr(left, sources, query), " IN (", args, ?)]
  end

  defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
    [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
  end

  # A value in an array column or an array parameter
  defp expr({:in, _, [left, right]}, sources, query) do
    ["SCALAR_IN_ARRAY(", expr(left, sources, query), ", ", expr(right, sources, query), ?)]
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    [expr(arg, sources, query) | " IS NULL"]
  end

  defp expr({:not, _, [expr]}, sources, query) do
    ["NOT (", expr(expr, sources, query), ?)]
  end

  defp expr({:filter, _, [agg, filter]}, sources, query) do
    aggregate = expr(agg, sources, query)
    [aggregate, " FILTER (WHERE ", expr(filter, sources, query), ?)]
  end

  defp expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
    combinations =
      Enum.map(query.combinations, fn {type, combination_query} ->
        {type, put_in(combination_query.aliases[@parent_as], {parent_query, sources})}
      end)

    query = put_in(query.combinations, combinations)
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    [?(, all(query, subquery_as_prefix(sources)), ?)]
  end

  defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
    error!(query, "Druid adapter does not support keyword or interpolated fragments")
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map(parts, fn
      {:raw, part} -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
    |> parens_for_select
  end

  defp expr({:values, _, [types, _idx, num_rows]}, _, query) do
    [?(, values_list(types, num_rows, query), ?)]
  end

  defp expr({:literal, _, [literal]}, _sources, _query) do
    quote_name(literal)
  end

  defp expr({:splice, _, [{:^, _, [_, length]}]}, _sources, _query) do
    Enum.intersperse(List.duplicate(??, length), ?,)
  end

  defp expr({:selected_as, _, [name]}, _sources, _query) do
    [quote_name(name)]
  end

  # ago/2 and from_now/2 reach the adapter as datetime_add of a pinned now
  defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
    timestamp_add(datetime, count, interval, sources, query)
  end

  # Druid can't type a DATE parameter added to an interval without the cast
  defp expr({:date_add, _, [date, count, interval]}, sources, query) do
    date =
      case date do
        %Ecto.Query.Tagged{type: :date} -> date
        date -> %Ecto.Query.Tagged{value: date, type: :date}
      end

    ["CAST(", timestamp_add(date, count, interval, sources, query), " AS DATE)"]
  end

  defp expr({:ilike, _, [_, _]}, _sources, query) do
    error!(query, "ilike is not supported by Druid")
  end

  defp expr({:nth_value, _, _}, _sources, query) do
    error!(query, "nth_value is not supported by Druid")
  end

  defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
    aggregate = expr(agg, sources, query)
    [aggregate, " OVER " | quote_name(name)]
  end

  defp expr({:over, _, [agg, kw]}, sources, query) do
    aggregate = expr(agg, sources, query)
    [aggregate, " OVER " | window_exprs(kw, sources, query)]
  end

  defp expr({:{}, _, elems}, sources, query) do
    [?(, Enum.map_intersperse(elems, ?,, &expr(&1, sources, query)), ?)]
  end

  defp expr({:count, _, []}, _sources, _query), do: "count(*)"

  # JSON_VALUE returns a scalar, so the path compares with strings and
  # numbers. Use json_query/2 for an object or array.
  defp expr({:json_extract_path, _, [expr, path]}, sources, query) do
    path =
      Enum.map(path, fn
        binary when is_binary(binary) -> json_path_key(binary, query)
        integer when is_integer(integer) -> "[#{integer}]"
      end)

    ["JSON_VALUE(", expr(expr, sources, query), ", '$", path, "')"]
  end

  defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
    {modifier, args} =
      case args do
        [rest, :distinct] -> {"DISTINCT ", [rest]}
        _ -> {[], args}
      end

    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]

      {:fun, fun} ->
        [fun, ?(, modifier, Enum.map_intersperse(args, ", ", &expr(&1, sources, query)), ?)]
    end
  end

  defp expr(list, _sources, query) when is_list(list) do
    error!(query, "Array type is not supported by Druid")
  end

  defp expr(%Decimal{} = decimal, _sources, _query) do
    Decimal.to_string(decimal, :normal)
  end

  defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
       when is_binary(binary) do
    hex = Base.encode16(binary, case: :lower)
    [?x, ?', hex, ?']
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: :complex}, sources, query) do
    expr(other, sources, query)
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
    ["CAST(", expr(other, sources, query), " AS ", cast_type(type, query), ?)]
  end

  defp expr(nil, _sources, _query), do: "NULL"
  defp expr(true, _sources, _query), do: "TRUE"
  defp expr(false, _sources, _query), do: "FALSE"

  defp expr(literal, _sources, _query) when is_binary(literal) do
    [?', escape_string(literal), ?']
  end

  defp expr(literal, _sources, _query) when is_integer(literal) do
    Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    # Druid doesn't support float cast
    Float.to_string(literal)
  end

  defp expr(expr, _sources, query) do
    error!(query, "unsupported expression: #{inspect(expr)}")
  end

  defp values_list(types, num_rows, query) do
    rows = Enum.to_list(1..num_rows)

    [
      "VALUES ",
      Enum.map_intersperse(rows, ?,, fn _ ->
        ["ROW(", values_expr(types, query), ?)]
      end)
    ]
  end

  defp values_expr(types, query) do
    Enum.map_intersperse(types, ?,, fn {_field, type} ->
      ["CAST(", ??, " AS ", cast_type(type, query), ?)]
    end)
  end

  # The datetime comes before the count, as Ecto orders their parameters,
  # so this multiplies an interval rather than calling TIMESTAMPADD
  defp timestamp_add(datetime, count, interval, sources, query) do
    [
      ?(,
      expr(datetime, sources, query),
      " + (",
      expr(interval_count(count), sources, query),
      ") * " | interval_literal(interval)
    ]
  end

  # Druid gets a multiple of INTERVAL '1' WEEK wrong, and keeps only
  # milliseconds, so a microsecond is a thousandth of a millisecond
  defp interval_literal("week"), do: "INTERVAL '7' DAY)"
  defp interval_literal("millisecond"), do: "INTERVAL '0.001' SECOND)"
  defp interval_literal("microsecond"), do: "INTERVAL '0.001' SECOND / 1000)"
  defp interval_literal(unit), do: ["INTERVAL '1' ", String.upcase(unit), ?)]

  # Ecto tags a literal count as a decimal, which is sent as the number
  defp interval_count(%Ecto.Query.Tagged{value: count, type: type})
       when type in [:decimal, :float, :integer],
       do: interval_count(count)

  defp interval_count({:-, meta, [count]}), do: {:-, meta, [interval_count(count)]}
  defp interval_count(count), do: count

  defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
    do: paren_expr(expr, sources, query)

  defp op_to_binary({:is_nil, _, [_]} = expr, sources, query),
    do: paren_expr(expr, sources, query)

  defp op_to_binary(expr, sources, query),
    do: expr(expr, sources, query)

  defp create_names(%{sources: sources}, as_prefix) do
    create_names(sources, 0, tuple_size(sources), as_prefix) |> List.to_tuple()
  end

  defp create_names(sources, pos, limit, as_prefix) when pos < limit do
    [create_name(sources, pos, as_prefix) | create_names(sources, pos + 1, limit, as_prefix)]
  end

  defp create_names(_sources, pos, pos, as_prefix) do
    [as_prefix]
  end

  defp subquery_as_prefix(sources) do
    [?s | :erlang.element(tuple_size(sources), sources)]
  end

  defp create_name(sources, pos, as_prefix) do
    case elem(sources, pos) do
      {:fragment, _, _} ->
        {nil, as_prefix ++ [?f | Integer.to_string(pos)], nil}

      {:values, _, _} ->
        {nil, as_prefix ++ [?v | Integer.to_string(pos)], nil}

      {table, schema, prefix} ->
        name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
        {quote_table(prefix, table), name, schema}

      %Ecto.SubQuery{} ->
        {nil, as_prefix ++ [?s | Integer.to_string(pos)], nil}
    end
  end

  defp create_alias(<<first, _rest::binary>>) when first in ?a..?z when first in ?A..?Z do
    first
  end

  defp create_alias(_) do
    ?t
  end

  ## Helpers

  defp get_source(query, sources, ix, {:fragment, meta, [{:raw, "UNNEST(" <> _} | _] = parts}) do
    {_expr, name, _schema} = elem(sources, ix)

    case List.pop_at(parts, -1) do
      {{:raw, ") AS " <> cols}, core} ->
        {expr({:fragment, meta, core ++ [raw: ")"]}, sources, query), [name, ?\s, cols]}

      _ ->
        {expr({:fragment, meta, parts}, sources, query), name}
    end
  end

  defp get_source(query, sources, ix, source) do
    {expr, name, _schema} = elem(sources, ix)
    name = maybe_add_column_names(source, name)
    {expr || expr(source, sources, query), name}
  end

  defp get_parent_sources_ix(query, as) do
    case query.aliases[@parent_as] do
      {%{aliases: %{^as => ix}}, sources} -> {ix, sources}
      {%{} = parent, _sources} -> get_parent_sources_ix(parent, as)
    end
  end

  defp maybe_add_column_names({:values, _, [types, _, _]}, name) do
    fields = Keyword.keys(types)
    [name, ?\s, ?(, quote_names(fields), ?)]
  end

  defp maybe_add_column_names(_, name), do: name

  defp quote_name(name) when is_atom(name) do
    quote_name(Atom.to_string(name))
  end

  defp quote_name(name) when is_binary(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad literal/field/table name #{inspect(name)} (\" is not permitted)")
    end

    [?", name, ?"]
  end

  defp quote_names(names), do: Enum.map_intersperse(names, ?,, &quote_name/1)

  defp quote_table(nil, name), do: quote_table(name)
  defp quote_table(prefix, name), do: [quote_table(prefix), ?., quote_table(name)]

  defp quote_table(name) when is_atom(name),
    do: quote_table(Atom.to_string(name))

  defp quote_table(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad table name #{inspect(name)}")
    end

    [?", name, ?"]
  end

  # Druid SQL strings don't treat backslash as an escape character, so only
  # single quotes are doubled
  defp escape_string(value) when is_binary(value) do
    :binary.replace(value, "'", "''", [:global])
  end

  # Druid's JSONPath reads ['key'] up to the next quote and has no way to
  # escape one, so a key with a single quote can't be addressed
  defp json_path_key(key, query) do
    if String.contains?(key, "'") do
      error!(query, "Druid JSON paths can't contain a key with a single quote: #{inspect(key)}")
    end

    ["[''", key, "'']"]
  end

  @datetime_types [:utc_datetime, :utc_datetime_usec, :naive_datetime, :naive_datetime_usec]

  defp cast_type(type, _query) when type in [:id, :integer], do: "BIGINT"
  defp cast_type(:float, _query), do: "DOUBLE"
  defp cast_type(:decimal, _query), do: "DECIMAL"
  defp cast_type(:boolean, _query), do: "BOOLEAN"
  defp cast_type(type, _query) when type in [:string, :binary_id, :uuid], do: "VARCHAR"
  defp cast_type(:date, _query), do: "DATE"
  defp cast_type(type, _query) when type in @datetime_types, do: "TIMESTAMP"

  defp cast_type(type, query) when type == :map or (is_tuple(type) and elem(type, 0) == :map),
    do: error!(query, "Druid can't cast to #{inspect(type)}. Use parse_json/1 instead")

  defp cast_type(type, query), do: error!(query, "Druid can't cast to #{inspect(type)}")

  defp error!(nil, message) do
    raise ArgumentError, message
  end

  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end
end
