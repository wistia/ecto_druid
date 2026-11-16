defmodule Druid.TasksBackfillTest do
  use ExUnit.Case, async: true
  alias Druid.Tasks
  alias Druid.Tasks.Run
  alias Ecto.Adapters.Druid.TestRepo

  doctest Druid.Tasks

  @moduletag :tmp_dir

  @template """
  {
    "type": "index_parallel",
    "spec": {
      "ioConfig": {
        "inputSource": {"type": "s3", "prefixes": <%= partition_prefixes "s3://bucket/events", @interval, "year=%Y/month=%m/day=%d/" %>}
      },
      "dataSchema": {
        "dataSource": "events",
        "granularitySpec": {"intervals": [<%= json to_string(@interval) %>]},
        "start": <%= json @start %>,
        "label": <%= json @label %>
      }
    }
  }
  """

  defp write_template!(dir) do
    File.write!(Path.join(dir, "events.json.eex"), @template)
  end

  defp opts(dir, extra) do
    Keyword.merge([path: dir, assigns: %{label: "x"}, poll_interval: 1], extra)
  end

  # A fake Overlord. Submitted tasks are named task-1, task-2, ... Each
  # reports RUNNING for `polls` status checks, then FAILED if its number is
  # in `fail`, or SUCCESS. `load` is the segments-left sequence for load
  # status requests.
  defp druid(opts \\ []) do
    polls = Keyword.get(opts, :polls, 1)
    fail = Keyword.get(opts, :fail, [])
    reject = Keyword.get(opts, :reject, [])
    test_pid = self()

    {:ok, agent} =
      Agent.start_link(fn -> %{next: 1, checks: %{}, load: Keyword.get(opts, :load, [0])} end)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, conn.path_info} do
        {"POST", ["druid", "indexer", "v1", "task"]} ->
          n = Agent.get_and_update(agent, &{&1.next, %{&1 | next: &1.next + 1}})
          send(test_pid, {:submit, n, Jason.decode!(body)})

          if n in reject do
            conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad task"})
          else
            Req.Test.json(conn, %{"task" => "task-#{n}"})
          end

        {"POST", ["druid", "indexer", "v1", "taskStatus"]} ->
          ids = Jason.decode!(body)
          send(test_pid, {:statuses, ids})

          statuses =
            Agent.get_and_update(agent, fn state ->
              checks = Enum.reduce(ids, state.checks, &Map.update(&2, &1, 1, fn c -> c + 1 end))

              {Map.new(ids, &{&1, status(&1, checks[&1], polls, fail)}),
               %{state | checks: checks}}
            end)

          Req.Test.json(conn, Map.reject(statuses, fn {_id, s} -> is_nil(s) end))

        {"GET", ["druid", "coordinator", "v1", "datasources", ds, "loadstatus"]} ->
          send(test_pid, {:loadstatus, ds, URI.decode_query(conn.query_string)})

          left =
            Agent.get_and_update(agent, fn
              %{load: [last]} = s -> {last, s}
              %{load: [next | rest]} = s -> {next, %{s | load: rest}}
            end)

          Req.Test.json(conn, %{ds => left})
      end
    end
  end

  defp status("missing-" <> _, _checks, _polls, _fail), do: nil

  defp status("task-" <> n = id, checks, polls, fail) do
    state =
      cond do
        checks <= polls -> "RUNNING"
        String.to_integer(n) in fail -> "FAILED"
        true -> "SUCCESS"
      end

    %{"id" => id, "status" => state, "duration" => 100, "errorMsg" => nil}
  end

  describe "intervals/3" do
    test "splits a range into days, ending at `to`" do
      assert Tasks.intervals(~D[2026-11-01], ~U[2026-11-03 12:00:00Z]) |> Enum.map(&to_string/1) ==
               [
                 "2026-11-01T00:00:00Z/2026-11-02T00:00:00Z",
                 "2026-11-02T00:00:00Z/2026-11-03T00:00:00Z",
                 "2026-11-03T00:00:00Z/2026-11-03T12:00:00Z"
               ]
    end

    test "takes hour, week, month and counted steps" do
      assert length(Tasks.intervals("2026-11-01", "2026-11-02", step: :hour)) == 24
      assert length(Tasks.intervals("2026-11-01", "2026-11-02", step: {6, :hour})) == 4
      assert length(Tasks.intervals(~D[2026-11-02], ~D[2026-11-30], step: :week)) == 4

      assert Tasks.intervals(~D[2026-01-31], ~D[2026-04-01], step: :month)
             |> Enum.map(&Date.to_iso8601(DateTime.to_date(&1.start))) ==
               ["2026-01-31", "2026-02-28", "2026-03-31"]
    end

    test "takes ISO 8601 date-times" do
      assert [interval] = Tasks.intervals("2026-11-01T05:00:00Z", "2026-11-02T05:00:00Z")
      assert interval.start == ~U[2026-11-01 05:00:00Z]
    end

    test "raises on a bad range, step or time zone" do
      assert_raise ArgumentError, ~r/before/, fn ->
        Tasks.intervals(~D[2026-11-02], ~D[2026-11-01])
      end

      assert_raise ArgumentError, ~r/:step/, fn ->
        Tasks.intervals(~D[2026-11-01], ~D[2026-11-02], step: :minute)
      end

      assert_raise ArgumentError, ~r/ISO 8601/, fn -> Tasks.intervals("nope", "2026-11-02") end

      assert_raise ArgumentError, ~r/needs a time zone database/, fn ->
        Tasks.intervals(~D[2026-11-01], ~D[2026-11-02], time_zone: "America/New_York")
      end
    end
  end

  describe "partition_prefixes/4" do
    test "lists one prefix per UTC day the interval touches" do
      interval = Ecto.Druid.Interval.new(~U[2026-11-01 05:00:00Z], ~U[2026-11-02 05:00:00Z])

      assert Tasks.partition_prefixes("s3://bucket/events/", interval, "day=%d/") ==
               ["s3://bucket/events/day=01/", "s3://bucket/events/day=02/"]
    end

    test "lists hours when the format has %H" do
      assert Tasks.partition_prefixes("b", "2026-11-01T22:30:00Z/2026-11-02T00:00:00Z", "%d/%H") ==
               ["b/01/22", "b/01/23"]
    end

    test "takes date bounds and raises on periods" do
      assert Tasks.partition_prefixes("b", "2026-11-01/2026-11-03", "%d") == ["b/01", "b/02"]

      assert_raise ArgumentError, ~r/date or date-time bounds/, fn ->
        Tasks.partition_prefixes("b", "2026-11-01/P1D", "%d")
      end
    end
  end

  describe "backfill/5" do
    test "renders one task per interval with interval assigns", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-03],
          opts(dir, dry_run: true)
        )

      assert [%Run{name: "events", data_source: "events", task_id: nil, spec: spec}, _] = runs

      assert spec["spec"]["dataSchema"]["granularitySpec"]["intervals"] ==
               ["2026-11-01T00:00:00Z/2026-11-02T00:00:00Z"]

      assert spec["spec"]["dataSchema"]["start"] == "2026-11-01T00:00:00Z"
      assert spec["spec"]["dataSchema"]["label"] == "x"

      assert spec["spec"]["ioConfig"]["inputSource"]["prefixes"] ==
               ["s3://bucket/events/year=2026/month=11/day=01/"]

      refute_received {:submit, _, _}
    end

    test "renders every task before submitting any", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "events.json.eex"), ~s({"x": <%= @missing %>}))

      assert_raise Tasks.Error, ~r/@missing/, fn ->
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-03],
          opts(dir, plug: druid())
        )
      end

      refute_received {:submit, _, _}
    end

    test "submits every task and waits for them", %{tmp_dir: dir} do
      write_template!(dir)
      test_pid = self()

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-04],
          opts(dir,
            plug: druid(),
            on_submit: &send(test_pid, {:on_submit, &1.task_id}),
            on_progress: &send(test_pid, {:progress, &1})
          )
        )

      assert Enum.map(runs, & &1.task_id) == ["task-1", "task-2", "task-3"]
      assert Enum.all?(runs, &Run.succeeded?/1)

      # All submitted up front, then checked in one request per poll
      assert_received {:submit, 1, _}
      assert_received {:submit, 2, _}
      assert_received {:submit, 3, _}
      assert_received {:statuses, ["task-1", "task-2", "task-3"]}

      assert_received {:on_submit, "task-1"}
      assert_received {:progress, %{total: 3, running: 3}}
      assert_received {:progress, %{total: 3, succeeded: 3, running: 0}}
    end

    test ":concurrency limits how many run at once", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-04],
          opts(dir, plug: druid(), concurrency: 1)
        )

      assert Enum.all?(runs, &Run.succeeded?/1)

      assert_received {:submit, 1, _}
      assert_received {:statuses, ["task-1"]}
      assert_received {:statuses, ["task-1"]}
      assert_received {:submit, 2, _}
      assert_received {:statuses, ["task-2"]}
    end

    test "reports failed and rejected tasks without stopping the rest", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-04],
          opts(dir, plug: druid(fail: [1], reject: [2]))
        )

      assert [
               %Run{task_id: "task-1", error: %Tasks.Error{reason: :failed}},
               %Run{task_id: nil, error: %Druid.Client.RequestError{status: 400}},
               %Run{task_id: "task-3", error: nil, status: %{"status" => "SUCCESS"}}
             ] = runs
    end

    test "await: false returns once every task is submitted", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-03],
          opts(dir, plug: druid(), await: false)
        )

      assert Enum.map(runs, & &1.task_id) == ["task-1", "task-2"]
      assert Enum.all?(runs, &is_nil(&1.status))
      refute_received {:statuses, _}
    end

    test "times out, marking unsubmitted tasks too", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-03],
          opts(dir, plug: druid(polls: 1000), concurrency: 1, timeout: 20, poll_interval: 5)
        )

      assert [
               %Run{task_id: "task-1", error: %Tasks.Error{reason: :timeout}},
               %Run{task_id: nil, error: %Tasks.Error{reason: :timeout}}
             ] = runs
    end

    test "waits for the backfilled interval's segments", %{tmp_dir: dir} do
      write_template!(dir)

      runs =
        Tasks.backfill(
          TestRepo,
          "events",
          ~D[2026-11-01],
          ~D[2026-11-03],
          opts(dir, plug: druid(load: [3, 0]), wait_for_segments: true)
        )

      assert Enum.all?(runs, &Run.succeeded?/1)

      assert_received {:loadstatus, "events", params}
      assert params["interval"] == "2026-11-01T00:00:00Z/2026-11-03T00:00:00Z"
      assert_received {:loadstatus, "events", _}
    end
  end

  describe "await_all/3 and statuses/3" do
    test "waits for task IDs" do
      runs =
        Tasks.await_all(TestRepo, ["task-1", "task-2"], plug: druid(fail: [2]), poll_interval: 1)

      assert [%Run{status: %{"status" => "SUCCESS"}, error: nil}, %Run{error: %Tasks.Error{}}] =
               runs
    end

    test "fails tasks Druid doesn't know" do
      assert [%Run{error: %Tasks.Error{message: "Druid has no task missing-1"}}] =
               Tasks.await_all(TestRepo, ["missing-1"], plug: druid())
    end

    test "statuses/3 checks once without waiting" do
      assert [%Run{status: %{"status" => "RUNNING"}, error: nil}] =
               Tasks.statuses(TestRepo, ["task-1"], plug: druid())

      assert Tasks.progress(Tasks.statuses(TestRepo, ["task-1"], plug: druid())) ==
               %{total: 1, succeeded: 0, failed: 0, running: 1, pending: 0}
    end
  end

  test "Run.to_map/1 and from_map/1 round trip" do
    [interval] = Tasks.intervals(~D[2026-11-01], ~D[2026-11-02])
    run = %Run{name: "events", interval: interval, data_source: "events", task_id: "t"}

    assert run |> Run.to_map() |> Jason.encode!() |> Jason.decode!() |> Run.from_map() ==
             %{
               run
               | interval: Ecto.Druid.Interval.new("2026-11-01T00:00:00Z", "2026-11-02T00:00:00Z")
             }
  end
end
