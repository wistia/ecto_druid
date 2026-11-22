defmodule Ecto.Druid.Fixtures do
  @moduledoc """
  Loads test data into Druid once, before a test suite runs, so tests that
  query a real Druid can share it instead of ingesting their own.

      # test/test_helper.exs
      Ecto.Druid.Fixtures.load!(MyApp.DruidRepo, [
        {MyApp.PageView, "test/fixtures/page_views.jsonl"},
        {MyApp.Edit, [
          %{"timestamp" => "2016-06-27T01:00:00Z", "channel" => "#en.wikipedia", "added" => 31},
          %{"timestamp" => "2016-06-27T02:00:00Z", "channel" => "#de.wikipedia", "added" => 12}
        ]}
      ])

      ExUnit.start()

  Each fixture's rows are ingested with a native batch task, and replace
  everything already in the data source, so every run starts from the same
  data. The data sources load at the same time, and `load!/3` returns once
  their segments are loaded and the Broker lists them, so the first test
  can query them.

  The tasks go to the repo's `:tasks` host, as in `Druid.Tasks`, and the
  readiness check to the repo's own host.

  See the [Testing guide](testing.md) for running these tests separately
  from stubbed ones.

  ## Fixtures

  A fixture is `{schema, rows}` or `{schema, rows, opts}`.

  `schema` is a module that uses `Ecto.Druid.Schema`. Its generated
  `dataSchema` (see `Ecto.Druid.Schema.Spec.data_schema/2`) ingests the
  rows into the schema's source, so `:from` transforms, rollup and metrics
  such as sketches apply as they do in production. Or `schema` is a data
  source name, with its `dataSchema` given in the `:data_schema` option.

  `rows` are the input records, as the data source's ingestion reads them:
  keyed by input field names, which aren't always the column names (the
  timestamp is read from `"timestamp"` unless the schema says otherwise). They
  are a list of maps, or the path to a file of JSON lines.

  ## Fixture options

    * `:data_schema` - The `dataSchema` of a fixture given by data source
      name, as a map. Its `dataSource` and `granularitySpec` intervals are
      set by `load!/3`.
    * `:input_format` - Druid's `inputFormat` for a file of rows. Defaults to
      `%{"type" => "json"}`. For example, `%{"type" => "csv",
      "findColumnsFromHeader" => true}`.
    * `:segment_granularity` - Defaults to `"DAY"`, which makes fewer
      segments than the schema's usual `"HOUR"` and loads faster.
    * `:data_source`, `:query_granularity`, `:rollup`, `:transforms`,
      `:filter`, `:merge` - As in `Ecto.Druid.Schema.Spec.data_schema/2`.

  ## Limits

  The rows are sent inline in the task spec, which Druid stores in its
  metadata database, so fixtures suit thousands of rows rather than
  millions.

  Tests should only read fixture data sources. A test that writes to one
  changes it for the tests that run after, until the next run reloads it.
  A test that writes should use a data source of its own, and delete it with
  `drop!/3` when it exits.
  """

  alias Druid.Tasks.{Error, Run}

  # Every time chunk, so the task drops data outside the fixture's own rows
  @all_time "1000-01-01/3000-01-01"
  # Druid's whole timeline. A kill task only deletes segments that lie
  # inside its interval, and one written with PARTITIONED BY ALL covers it all.
  @eternity "-146136543-09-08T08:23:32.096Z/146140482-04-24T15:36:27.903Z"
  @data_schema_opts [
    :data_source,
    :segment_granularity,
    :query_granularity,
    :rollup,
    :transforms,
    :filter,
    :merge
  ]

  @doc """
  Loads `fixtures` into Druid, replacing what's in their data sources, and
  waits until they can be queried.

  Raises `ArgumentError` for a malformed fixture, and `Druid.Tasks.Error`
  if a task fails or doesn't finish in time.

  ## Options

    * `:timeout` - How long to wait for all of the fixtures, in
      milliseconds. Defaults to `300_000`.
    * `:poll_interval` - How often to check on the tasks, in milliseconds.
      Defaults to `500`.
    * `:host`, `:port`, `:scheme` and the other connection options of
      `Druid.Tasks`.
  """
  @spec load!(Ecto.Repo.t(), [tuple()], Keyword.t()) :: :ok
  def load!(repo, fixtures, opts \\ []) do
    runs =
      fixtures
      |> Enum.map(&spec/1)
      |> check_unique!()
      |> Enum.map(fn spec -> %Run{data_source: Druid.Tasks.data_source(spec), spec: spec} end)

    opts =
      opts
      |> Keyword.put_new(:timeout, 300_000)
      |> Keyword.put_new(:poll_interval, 500)
      |> Keyword.put(:wait_for_segments, true)

    case Enum.filter(Druid.Tasks.await_all(repo, runs, opts), & &1.error) do
      [] ->
        :ok

      [first | _] = failed ->
        details =
          Enum.map_join(failed, "; ", &"#{&1.data_source}: #{Exception.message(&1.error)}")

        raise Error,
          message: "couldn't load fixtures into #{details}",
          reason: Map.get(first.error, :reason),
          task_id: first.task_id,
          status: first.status
    end
  end

  @doc """
  Permanently deletes data sources from Druid, and waits until the Broker no
  longer lists them.

  > #### This deletes data {: .warning}
  >
  > The data sources' segments are removed from the metadata store and from
  > deep storage, and can't be recovered. Only point this at a test cluster,
  > and only at data sources your tests create.

  Use it to remove a data source a test wrote to, when the test exits:

      setup do
        on_exit(fn -> Ecto.Druid.Fixtures.drop!(MyApp.DruidRepo, "edits_test") end)
      end

  For each data source, it shuts down the ingestion tasks that are running
  or waiting to, marks every segment unused so Historicals drop them, and
  runs a `kill` task over Druid's whole timeline. Shutting tasks down first
  matters when a test fails or times out while it waits on one: the task
  keeps running, holding a task slot, and could publish segments after the
  drop. Waiting for the Broker means a test that writes to the same name
  next doesn't read the old rows.

  It doesn't terminate supervisors, or remove compaction configs, retention
  rules or lookups. A data source that doesn't exist is fine, so it can run
  after a test that failed before writing anything.

  Returns `:ok`. Raises `Druid.Tasks.Error` if a request or the `kill` task
  fails, or it doesn't finish in time.

  ## Options

    * `:timeout` - How long to wait for all of it, in milliseconds. Defaults
      to `120_000`.
    * `:poll_interval` - How often to check, in milliseconds. Defaults to
      `500`.
    * `:host`, `:port`, `:scheme` and the other connection options of
      `Druid.Tasks`. Tasks and segments are managed on the repo's `:tasks`
      host, and the Broker is asked on the repo's own host.
  """
  @spec drop!(Ecto.Repo.t(), String.t() | [String.t()], Keyword.t()) :: :ok
  def drop!(repo, data_sources, opts \\ []) do
    data_sources = data_sources |> List.wrap() |> Enum.map(&data_source_name!/1)
    deadline = Druid.Poll.deadline(Keyword.get(opts, :timeout, 120_000))
    poll_interval = Keyword.get(opts, :poll_interval, 500)
    tasks_opts = Keyword.drop(opts, [:timeout, :poll_interval])

    request_opts =
      Druid.SpecTemplates.request_opts(repo, Druid.SpecTemplates.config(repo, :tasks, tasks_opts))

    # SQL goes to the host the repo queries, since the :tasks host can be an
    # Overlord, which doesn't serve SQL
    broker_opts = Druid.SpecTemplates.request_opts(repo, Keyword.take(opts, [:plug, :adapter]))

    shutdown_tasks!(data_sources, deadline, poll_interval, request_opts)

    kills =
      for data_source <- data_sources do
        Druid.Client.DataSource.mark_unused(data_source)
        |> drop_request!(request_opts, data_source)

        {data_source, submit_kill!(repo, data_source, tasks_opts)}
      end

    await_opts = Keyword.merge(tasks_opts, poll_interval: poll_interval)

    for {data_source, task_id} <- kills do
      opts = Keyword.put(await_opts, :timeout, Druid.Poll.remaining(deadline))

      case Druid.Tasks.await(repo, task_id, opts) do
        {:ok, _status} -> :ok
        {:error, error} -> raise drop_error(data_source, error)
      end
    end

    await_unlisted!(data_sources, deadline, poll_interval, broker_opts)
  end

  defp data_source_name!(name) when is_binary(name) and name != "", do: name

  defp data_source_name!(other) do
    raise ArgumentError, "expected a data source name, got: #{inspect(other)}"
  end

  @active_states ~w(running pending waiting)

  defp shutdown_tasks!(data_sources, deadline, poll_interval, request_opts) do
    # Druid 32 to 39 answer shutdownAllTasks with a 404, so each task is shut
    # down by id. One that has just finished answers with an error, which is
    # fine here.
    for task_id <- active_tasks!(data_sources, request_opts) do
      Druid.Client.Task.shutdown(task_id) |> Druid.Client.request(request_opts)
    end

    # Shutting down is asynchronous, and a task still running could publish
    # segments after the kill
    check = fn ->
      case active_tasks!(data_sources, request_opts) do
        [] -> {:done, :ok}
        task_ids -> {:wait, task_ids}
      end
    end

    case Druid.Poll.poll(deadline, poll_interval, check) do
      {:ok, :ok} ->
        :ok

      {:timeout, task_ids} ->
        raise Error,
          message: "timed out shutting down tasks #{inspect(task_ids)} to drop data sources",
          reason: :timeout
    end
  end

  defp active_tasks!(data_sources, request_opts) do
    for data_source <- data_sources,
        state <- @active_states,
        %{"id" => id} <-
          Druid.Client.Task.all(state: state, datasource: data_source)
          |> drop_request!(request_opts, data_source),
        uniq: true,
        do: id
  end

  defp submit_kill!(repo, data_source, opts) do
    task = %{"type" => "kill", "dataSource" => data_source, "interval" => @eternity}

    case Druid.Tasks.submit(repo, task, opts) do
      {:ok, task_id} -> task_id
      {:error, error} -> raise drop_error(data_source, error)
    end
  end

  # Historicals drop the segments on the Coordinator's next run, and the
  # Broker stops listing the data source once none are served
  defp await_unlisted!(data_sources, deadline, poll_interval, broker_opts) do
    sql = Druid.Tasks.broker_lists_sql()

    listed? = fn data_source ->
      Druid.Client.SQL.query(sql, [%{type: "VARCHAR", value: data_source}])
      |> drop_request!(broker_opts, data_source)
      |> Enum.any?()
    end

    check = fn ->
      case Enum.filter(data_sources, listed?) do
        [] -> {:done, :ok}
        listed -> {:wait, listed}
      end
    end

    case Druid.Poll.poll(deadline, poll_interval, check) do
      {:ok, :ok} ->
        :ok

      {:timeout, listed} ->
        raise Error,
          message: "timed out waiting for the Broker to stop listing #{Enum.join(listed, ", ")}",
          reason: :timeout
    end
  end

  defp drop_request!(request, request_opts, data_source) do
    case Druid.Client.request(request, request_opts) do
      {:ok, body} -> body
      {:error, error} -> raise drop_error(data_source, error)
    end
  end

  # Keeps a failed or timed out kill task's details
  defp drop_error(data_source, error) do
    message = "couldn't drop #{data_source}: #{Exception.message(error)}"

    case error do
      %Error{} -> %{error | message: message}
      _ -> %Error{message: message}
    end
  end

  defp spec({source, rows}), do: spec({source, rows, []})

  defp spec({source, rows, opts}) when is_list(opts) do
    data_schema =
      source
      |> data_schema(opts)
      |> put_in([Access.key("granularitySpec", %{}), "intervals"], [@all_time])

    %{
      "type" => "index_parallel",
      "spec" => %{
        "ioConfig" => %{
          "type" => "index_parallel",
          "inputSource" => %{"type" => "inline", "data" => data!(source, rows)},
          "inputFormat" => input_format(rows, opts),
          "appendToExisting" => false,
          "dropExisting" => true
        },
        "tuningConfig" => %{
          "type" => "index_parallel",
          "partitionsSpec" => %{"type" => "dynamic"}
        },
        "dataSchema" => data_schema
      }
    }
  end

  defp spec(other) do
    raise ArgumentError,
          "expected a fixture as {schema, rows} or {schema, rows, opts}, got: #{inspect(other)}"
  end

  defp data_schema(name, opts) when is_binary(name) do
    case Keyword.fetch(opts, :data_schema) do
      {:ok, %{} = data_schema} ->
        # Through JSON, so atom keys become the string keys set below
        data_schema
        |> Jason.encode!()
        |> Jason.decode!()
        |> Map.put("dataSource", name)

      _ ->
        raise ArgumentError,
              "the #{name} fixture needs a :data_schema option, since it doesn't name a " <>
                "schema that uses Ecto.Druid.Schema"
    end
  end

  defp data_schema(schema, opts) when is_atom(schema) do
    unless Code.ensure_loaded?(schema) and function_exported?(schema, :__druid__, 1) do
      raise ArgumentError,
            "expected a fixture's schema to use Ecto.Druid.Schema, or to be a data source " <>
              "name, got: #{inspect(schema)}"
    end

    opts =
      opts
      |> Keyword.take(@data_schema_opts)
      |> Keyword.put_new(:segment_granularity, "DAY")

    Ecto.Druid.Schema.Spec.data_schema(schema, opts)
  end

  defp data!(source, path) when is_binary(path) do
    path |> File.read!() |> check_rows!(source)
  end

  defp data!(source, rows) when is_list(rows) do
    rows |> Enum.map_join("\n", &Jason.encode!/1) |> check_rows!(source)
  end

  defp check_rows!(data, source) do
    if String.trim(data) == "" do
      raise ArgumentError, "the #{label(source)} fixture has no rows"
    end

    data
  end

  defp input_format(path, opts) when is_binary(path),
    do: Keyword.get(opts, :input_format, %{"type" => "json"})

  defp input_format(_rows, _opts), do: %{"type" => "json"}

  defp check_unique!(specs) do
    specs
    |> Enum.frequencies_by(&Druid.Tasks.data_source/1)
    |> Enum.filter(fn {_data_source, count} -> count > 1 end)
    |> case do
      [] ->
        specs

      dupes ->
        names = dupes |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.join(", ")
        raise ArgumentError, "more than one fixture loads into: #{names}"
    end
  end

  defp label(source) when is_binary(source), do: source
  defp label(schema), do: inspect(schema)
end
