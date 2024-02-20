defmodule Ecto.Adapters.Druid.Query do
  @parent_as __MODULE__
  alias Ecto.Query.{BooleanExpr, JoinExpr, QueryExpr, WithExpr}

  def all(query, as_prefix \\ []) do
    sources = create_names(query, as_prefix)
    {select_distinct, order_by_distinct} = distinct(query.distinct, sources, query)

    cte = cte(query, sources)
    from = from(query, sources)
    select = select(query, select_distinct, sources)
    join = join(query, sources)
    where = where(query, sources)
    group_by = group_by(query, sources)
    having = having(query, sources)
    window = window(query, sources)
    combinations = combinations(query, as_prefix)
    order_by = order_by(query, order_by_distinct, sources)
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
    ilike: " ILIKE ",
    like: " LIKE "
  ]

  @binary_ops Keyword.keys(binary_ops)

  Enum.map(binary_ops, fn {op, str} ->
    defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

  defp select(%{select: %{fields: fields}} = query, select_distinct, sources) do
    ["SELECT", select_distinct, ?\s | select_fields(fields, sources, query)]
  end

  defp select_fields([], _sources, _query),
    do: "TRUE"

  defp select_fields(fields, sources, query) do
    Enum.map_intersperse(fields, ", ", fn
      {:&, _, [idx]} ->
        case elem(sources, idx) do
          {nil, source, nil} ->
            error!(
              query,
              "DruidSQL adapter does not support selecting all fields from fragment #{source}. " <>
                "Please specify exactly which fields you want to select"
            )

          {source, _, nil} ->
            error!(
              query,
              "DruidSQL adapter does not support selecting all fields from #{source} without a schema. " <>
                "Please specify a schema or specify exactly which fields you want to select"
            )

          {_, source, _} ->
            source
        end

      {key, value} ->
        [expr(value, sources, query), " AS " | quote_name(key)]

      value ->
        expr(value, sources, query)
    end)
  end

  defp distinct(nil, _, _), do: {[], []}
  defp distinct(%QueryExpr{expr: []}, _, _), do: {[], []}
  defp distinct(%QueryExpr{expr: true}, _, _), do: {" DISTINCT", []}
  defp distinct(%QueryExpr{expr: false}, _, _), do: {[], []}

  defp distinct(%QueryExpr{expr: exprs}, sources, query) do
    {[
       " DISTINCT ON (",
       Enum.map_intersperse(exprs, ", ", fn {_, expr} -> expr(expr, sources, query) end),
       ?)
     ], exprs}
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

  defp cte_expr({name, opts, cte}, sources, query) do
    materialized_opt =
      case opts[:materialized] do
        nil -> ""
        true -> "MATERIALIZED"
        false -> "NOT MATERIALIZED"
      end

    operation_opt = Map.get(opts, :operation)

    [quote_name(name), " AS ", materialized_opt, cte_query(cte, sources, query, operation_opt)]
  end

  defp cte_query(query, sources, parent_query, nil) do
    cte_query(query, sources, parent_query, :all)
  end

  defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, :update_all) do
    error!(query, "Druid adapter does not support CTE operation :update_all")
  end

  defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, :delete_all) do
    error!(query, "Druid adapter does not support CTE operation :delete_all")
  end

  defp cte_query(%Ecto.Query{} = query, _sources, _parent_query, :insert_all) do
    error!(query, "Druid adapter does not support CTE operation :insert_all")
  end

  defp cte_query(%Ecto.Query{} = query, sources, parent_query, :all) do
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    ["(", all(query, subquery_as_prefix(sources)), ")"]
  end

  defp cte_query(%QueryExpr{expr: expr}, sources, query, _operation) do
    expr(expr, sources, query)
  end

  defp join(%{joins: []}, _sources), do: []

  defp join(%{joins: joins} = query, sources) do
    [
      ?\s
      | Enum.map_intersperse(joins, ?\s, fn
          %JoinExpr{
            on: %QueryExpr{expr: expr},
            qual: qual,
            ix: ix,
            source: source,
            hints: hints
          } ->
            if hints != [] do
              error!(query, "table hints are not supported by DruidSQL")
            end

            {join, name} = get_source(query, sources, ix, source)
            [join_qual(qual, query), join, " AS ", name | join_on(qual, expr, sources, query)]
        end)
    ]
  end

  defp join_on(:cross, true, _sources, _query), do: []
  defp join_on(:cross_lateral, true, _sources, _query), do: []
  defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

  defp join_qual(:inner, _), do: "INNER JOIN "
  defp join_qual(:inner_lateral, _), do: "INNER JOIN LATERAL "
  defp join_qual(:left, _), do: "LEFT OUTER JOIN "
  defp join_qual(:left_lateral, _), do: "LEFT OUTER JOIN LATERAL "
  defp join_qual(:right, _), do: "RIGHT OUTER JOIN "
  defp join_qual(:full, _), do: "FULL OUTER JOIN "
  defp join_qual(:cross, _), do: "CROSS JOIN "
  defp join_qual(:cross_lateral, _), do: "CROSS JOIN LATERAL "

  defp join_qual(qual, query),
    do:
      error!(
        query,
        "join qualifier #{inspect(qual)} is not supported in the DruidSQL adapter"
      )

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
      | Enum.map_intersperse(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
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

  defp order_by(%{order_bys: []}, _distinct, _sources), do: []

  defp order_by(%{order_bys: order_bys} = query, distinct, sources) do
    order_bys = Enum.flat_map(order_bys, & &1.expr)
    order_bys = order_by_concat(distinct, order_bys)
    [" ORDER BY " | Enum.map_intersperse(order_bys, ", ", &order_by_expr(&1, sources, query))]
  end

  defp order_by_concat([head | left], [head | right]), do: [head | order_by_concat(left, right)]
  defp order_by_concat(left, right), do: left ++ right

  defp order_by_expr({dir, expr}, sources, query) do
    str = expr(expr, sources, query)

    case dir do
      :asc -> str
      :asc_nulls_last -> [str, " ASC NULLS LAST"]
      :asc_nulls_first -> [str, " ASC NULLS FIRST"]
      :desc -> [str, " DESC"]
      :desc_nulls_last -> [str, " DESC NULLS LAST"]
      :desc_nulls_first -> [str, " DESC NULLS FIRST"]
    end
  end

  defp limit(%{limit: nil}, _sources), do: []

  defp limit(%{limit: %{with_ties: true}, order_bys: []} = query, _sources) do
    error!(
      query,
      "DruidSQL adapter requires an `order_by` clause if the " <>
        "`:with_ties` limit option is `true`"
    )
  end

  defp limit(%{limit: %{expr: expr, with_ties: true}} = query, sources) do
    [" FETCH FIRST ", expr(expr, sources, query), " ROWS WITH TIES"]
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
  defp lock(%{lock: binary}, _sources) when is_binary(binary), do: [?\s, binary]
  defp lock(%{lock: expr} = query, sources), do: [?\s | expr(expr, sources, query)]

  defp boolean(_name, [], _sources, _query), do: []

  defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
    [
      name
      | Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
          %BooleanExpr{expr: expr, op: op}, {op, acc} ->
            {op, [acc, operator_to_boolean(op), paren_expr(expr, sources, query)]}

          %BooleanExpr{expr: expr, op: op}, {_, acc} ->
            {op, [?(, acc, ?), operator_to_boolean(op), paren_expr(expr, sources, query)]}
        end)
        |> elem(1)
    ]
  end

  defp operator_to_boolean(:and), do: " AND "
  defp operator_to_boolean(:or), do: " OR "

  defp parens_for_select([first_expr | _] = expr) do
    if is_binary(first_expr) and String.match?(first_expr, ~r/^\s*select\s/i) do
      [?(, expr, ?)]
    else
      expr
    end
  end

  defp paren_expr(expr, sources, query) do
    [?(, expr(expr, sources, query), ?)]
  end

  defp expr({:^, [], [ix]}, _sources, _query) do
    [?$, Integer.to_string(ix + 1)]
  end

  defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
       when is_atom(field) do
    {ix, sources} = get_parent_sources_ix(query, as)
    quote_qualified_name(field, sources, ix)
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
    quote_qualified_name(field, sources, idx)
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

  defp expr({:in, _, [left, {:^, _, [ix, _]}]}, sources, query) do
    [expr(left, sources, query), " = ANY($", Integer.to_string(ix + 1), ?)]
  end

  defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
    [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
  end

  defp expr({:in, _, [left, right]}, sources, query) do
    [expr(left, sources, query), " = ANY(", expr(right, sources, query), ?)]
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    [expr(arg, sources, query), " IS NULL"]
  end

  defp expr({:not, _, [expr]}, sources, query) do
    ["NOT (", expr(expr, sources, query), ?)]
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
    error!(query, "DruidSQL adapter does not support keyword or interpolated fragments")
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map(parts, fn
      {:raw, part} -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
    |> parens_for_select
  end

  defp expr({:values, _, [types, idx, num_rows]}, _, _query) do
    [?(, values_list(types, idx + 1, num_rows), ?)]
  end

  defp expr({:literal, _, [literal]}, _sources, _query) do
    quote_name(literal)
  end

  defp expr({:splice, _, [{:^, _, [idx, length]}]}, _sources, _query) do
    Enum.map_join(1..length, ",", &"$#{idx + &1}")
  end

  defp expr({:selected_as, _, [name]}, _sources, _query) do
    [quote_name(name)]
  end

  defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
    [
      expr(datetime, sources, query),
      type_unless_typed(datetime, "timestamp"),
      " + ",
      interval(count, interval, sources, query)
    ]
  end

  defp expr({:date_add, _, [date, count, interval]}, sources, query) do
    [
      ?(,
      expr(date, sources, query),
      type_unless_typed(date, "date"),
      " + ",
      interval(count, interval, sources, query),
      ")::date"
    ]
  end

  defp expr({:json_extract_path, _, [expr, path]}, sources, query) do
    json_extract_path(expr, path, sources, query)
  end

  defp expr({:filter, _, [agg, filter]}, sources, query) do
    aggregate = expr(agg, sources, query)
    [aggregate, " FILTER (WHERE ", expr(filter, sources, query), ?)]
  end

  defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
    aggregate = expr(agg, sources, query)
    [aggregate, " OVER " | quote_name(name)]
  end

  defp expr({:over, _, [agg, kw]}, sources, query) do
    aggregate = expr(agg, sources, query)
    [aggregate, " OVER ", window_exprs(kw, sources, query)]
  end

  defp expr({:{}, _, elems}, sources, query) do
    [?(, Enum.map_intersperse(elems, ?,, &expr(&1, sources, query)), ?)]
  end

  defp expr({:count, _, []}, _sources, _query), do: "count(*)"

  defp expr({:==, _, [{:json_extract_path, _, [expr, path]} = left, right]}, sources, query)
       when is_binary(right) or is_integer(right) or is_boolean(right) do
    case Enum.split(path, -1) do
      {path, [last]} when is_binary(last) ->
        extracted = json_extract_path(expr, path, sources, query)
        [?(, extracted, "@>'{", escape_json(last), ": ", escape_json(right) | "}')"]

      _ ->
        [maybe_paren(left, sources, query), " = " | maybe_paren(right, sources, query)]
    end
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
        [maybe_paren(left, sources, query), op | maybe_paren(right, sources, query)]

      {:fun, fun} ->
        [fun, ?(, modifier, Enum.map_intersperse(args, ", ", &expr(&1, sources, query)), ?)]
    end
  end

  defp expr([], _sources, _query) do
    # We cannot compare in Druids with the empty array
    # i. e. `where array_column = ARRAY[];`
    # as that will result in an error:
    #   ERROR:  cannot determine type of empty array
    #   HINT:  Explicitly cast to the desired type, for example ARRAY[]::integer[].
    #
    # On the other side comparing with '{}' works
    # because '{}' represents the pseudo-type "unknown"
    # and thus the type gets inferred based on the column
    # it is being compared to so `where array_column = '{}';` works.
    "'{}'"
  end

  defp expr(list, sources, query) when is_list(list) do
    ["ARRAY[", Enum.map_intersperse(list, ?,, &expr(&1, sources, query)), ?]]
  end

  defp expr(%Decimal{} = decimal, _sources, _query) do
    Decimal.to_string(decimal, :normal)
  end

  defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
       when is_binary(binary) do
    ["'\\x", Base.encode16(binary, case: :lower), "'::bytea"]
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
    [maybe_paren(other, sources, query), ?:, ?: | tagged_to_db(type)]
  end

  defp expr(nil, _sources, _query), do: "NULL"
  defp expr(true, _sources, _query), do: "TRUE"
  defp expr(false, _sources, _query), do: "FALSE"

  defp expr(literal, _sources, _query) when is_binary(literal) do
    [?\', escape_string(literal), ?\']
  end

  defp expr(literal, _sources, _query) when is_integer(literal) do
    Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    [Float.to_string(literal), "::float"]
  end

  defp expr(expr, _sources, query) do
    error!(query, "unsupported expression: #{inspect(expr)}")
  end

  defp json_extract_path(expr, [], sources, query) do
    expr(expr, sources, query)
  end

  defp json_extract_path(expr, path, sources, query) do
    path = Enum.map_intersperse(path, ?,, &escape_json/1)
    [?(, expr(expr, sources, query), "#>'{", path, "}')"]
  end

  defp values_list(types, idx, num_rows) do
    rows = Enum.to_list(1..num_rows)

    [
      "VALUES ",
      intersperse_reduce(rows, ?,, idx, fn _, idx ->
        {value, idx} = values_expr(types, idx)
        {[?(, value, ?)], idx}
      end)
      |> elem(0)
    ]
  end

  defp values_expr(types, idx) do
    intersperse_reduce(types, ?,, idx, fn {_field, type}, idx ->
      {[?$, Integer.to_string(idx), ?:, ?: | tagged_to_db(type)], idx + 1}
    end)
  end

  defp type_unless_typed(%Ecto.Query.Tagged{}, _type), do: []
  defp type_unless_typed(_, type), do: [?:, ?:, type]

  # Always use the largest possible type for integers
  defp tagged_to_db(:id), do: "LONG"
  defp tagged_to_db(:integer), do: "LONG"
  defp tagged_to_db({:array, type}), do: [tagged_to_db(type), ?[, ?]]
  defp tagged_to_db(type), do: ecto_to_db(type)

  defp interval(count, interval, _sources, _query) when is_integer(count) do
    ["interval '", String.Chars.Integer.to_string(count), ?\s, interval, ?\']
  end

  defp interval(count, interval, _sources, _query) when is_float(count) do
    count = :erlang.float_to_binary(count, [:compact, decimals: 16])
    ["interval '", count, ?\s, interval, ?\']
  end

  defp interval(count, interval, sources, query) do
    [?(, expr(count, sources, query), "::numeric * ", interval(1, interval, sources, query), ?)]
  end

  defp maybe_paren({op, _, [_, _]} = expr, sources, query) when op in @binary_ops,
    do: paren_expr(expr, sources, query)

  defp maybe_paren({:is_nil, _, [_]} = expr, sources, query),
    do: paren_expr(expr, sources, query)

  defp maybe_paren(expr, sources, query),
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
        {quote_name(prefix, table), name, schema}

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

  defp quote_qualified_name(name, sources, ix) do
    {_, source, _} = elem(sources, ix)
    [source, ?. | quote_name(name)]
  end

  defp quote_names(names) do
    Enum.map_intersperse(names, ?,, &quote_name/1)
  end

  defp quote_name(nil, name), do: quote_name(name)

  defp quote_name(prefix, name), do: [quote_name(prefix), ?., quote_name(name)]

  defp quote_name(name) when is_atom(name) do
    quote_name(Atom.to_string(name))
  end

  defp quote_name(name) when is_binary(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad literal/field/index/table name #{inspect(name)} (\" is not permitted)")
    end

    [?", name, ?"]
  end

  defp intersperse_reduce(list, separator, user_acc, reducer, acc \\ [])

  defp intersperse_reduce([], _separator, user_acc, _reducer, acc),
    do: {acc, user_acc}

  defp intersperse_reduce([elem], _separator, user_acc, reducer, acc) do
    {elem, user_acc} = reducer.(elem, user_acc)
    {[acc | elem], user_acc}
  end

  defp intersperse_reduce([elem | rest], separator, user_acc, reducer, acc) do
    {elem, user_acc} = reducer.(elem, user_acc)
    intersperse_reduce(rest, separator, user_acc, reducer, [acc, elem, separator])
  end

  defp escape_string(value) when is_binary(value) do
    :binary.replace(value, "'", "''", [:global])
  end

  defp escape_json(value) when is_binary(value) do
    escaped =
      value
      |> escape_string()
      |> :binary.replace("\"", "\\\"", [:global])

    [?", escaped, ?"]
  end

  defp escape_json(value) when is_integer(value) do
    Integer.to_string(value)
  end

  defp escape_json(true), do: ["true"]
  defp escape_json(false), do: ["false"]

  defp ecto_to_db({:array, t}), do: [ecto_to_db(t), ?[, ?]]
  defp ecto_to_db(:id), do: "LONG"
  defp ecto_to_db(:identity), do: "LONG"
  defp ecto_to_db(:serial), do: "serial"
  defp ecto_to_db(:bigserial), do: "bigserial"
  defp ecto_to_db(:binary_id), do: "uuid"
  defp ecto_to_db(:string), do: "varchar"
  defp ecto_to_db(:binary), do: "bytea"
  defp ecto_to_db(:map), do: Application.fetch_env!(:ecto_sql, :Druids_map_type)
  defp ecto_to_db({:map, _}), do: Application.fetch_env!(:ecto_sql, :Druids_map_type)
  defp ecto_to_db(:time_usec), do: "time"
  defp ecto_to_db(:utc_datetime), do: "timestamp"
  defp ecto_to_db(:utc_datetime_usec), do: "timestamp"
  defp ecto_to_db(:naive_datetime), do: "timestamp"
  defp ecto_to_db(:naive_datetime_usec), do: "timestamp"
  defp ecto_to_db(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp ecto_to_db(type) do
    raise ArgumentError,
          "unsupported type `#{inspect(type)}`. The type can either be an atom, a string " <>
            "or a tuple of the form `{:map, t}` or `{:array, t}` where `t` itself follows the same conditions."
  end

  defp error!(nil, message) do
    raise ArgumentError, message
  end

  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end
end
