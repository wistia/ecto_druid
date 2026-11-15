# Used by "mix format"
schema_dsl = [
  timestamp: 1,
  timestamp: 2,
  dimension: 2,
  dimension: 3,
  metric: 2,
  metric: 3
]

[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [sql_function: 1, sql_function: 2] ++ schema_dsl,
  # Lets apps with `import_deps: [:ecto_druid]` write the schema DSL without parens
  export: [locals_without_parens: schema_dsl]
]
