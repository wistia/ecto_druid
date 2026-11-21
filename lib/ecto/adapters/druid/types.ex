defmodule Ecto.Adapters.Druid.Types do
  @moduledoc false

  @datetime_types [
    :date,
    :utc_datetime,
    :utc_datetime_usec,
    :naive_datetime,
    :naive_datetime_usec
  ]

  @local_types [:date, :naive_datetime, :naive_datetime_usec]

  # Map elixir type to database type. Dumpers run in order, so custom types
  # (whose primitive type is passed as the first argument) must dump through
  # their own module rather than through the primitive type.
  def dumpers(:binary_id, value), do: [Ecto.UUID, value]
  def dumpers(:complex, value), do: [value]
  def dumpers(_type, ecto_type), do: [ecto_type]

  # Map database type to elixir type
  def loaders(:binary_id, value), do: [Ecto.UUID, value]
  def loaders(:complex, value), do: [value]

  def loaders(type, value) when type in @datetime_types,
    do: [&load_datetime(&1, type), value]

  def loaders(type, value), do: [type, value]

  # Druid returns DATE and TIMESTAMP values as ISO 8601 strings in the query's
  # sqlTimeZone, which defaults to UTC, such as "2016-06-27T00:00:00.000Z" or
  # "2016-06-26T19:00:00.000-05:00". Dates and naive datetimes keep the
  # wall-clock time in that zone, the way Druid reads a DATE or naive
  # TIMESTAMP parameter. UTC datetimes are shifted to UTC.
  defp load_datetime(value, type) when is_binary(value) and type in @local_types do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, naive} -> {:ok, convert_naive(naive, type)}
      {:error, _} -> :error
    end
  end

  defp load_datetime(value, _type) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> :error
    end
  end

  defp load_datetime(value, _type), do: {:ok, value}

  defp convert_naive(naive, :date), do: NaiveDateTime.to_date(naive)
  defp convert_naive(naive, _type), do: naive

  # Converts query params to Druid's typed parameters, for the sqlTimeZone in
  # a query's context
  def to_db_params(params, context) do
    time_zone = session_time_zone(context)
    Enum.map(params, &to_db(&1, time_zone))
  end

  # Type names must be Avatica SqlType values. `time_zone` is the query's
  # sqlTimeZone, or nil for UTC.
  def to_db(value, time_zone \\ nil)

  def to_db(value, _time_zone) when is_integer(value), do: db("BIGINT", value)
  def to_db(value, _time_zone) when is_float(value), do: db("DOUBLE", value)
  def to_db(value, _time_zone) when is_binary(value), do: db("VARCHAR", value)
  def to_db(value, _time_zone) when is_boolean(value), do: db("BOOLEAN", value)
  def to_db(nil, _time_zone), do: db("NULL", nil)
  def to_db(%DateTime{} = value, nil), do: db("TIMESTAMP", DateTime.to_iso8601(value))

  # Druid reads a TIMESTAMP parameter as a wall-clock time in sqlTimeZone and
  # ignores any offset in it, so a DateTime is sent as its time in that zone
  def to_db(%DateTime{} = value, time_zone),
    do: db("TIMESTAMP", value |> wall_clock(time_zone) |> NaiveDateTime.to_iso8601())

  def to_db(%NaiveDateTime{} = value, _time_zone),
    do: db("TIMESTAMP", NaiveDateTime.to_iso8601(value))

  def to_db(%Date{} = value, _time_zone), do: db("DATE", Date.to_iso8601(value))

  # Jason encodes a Decimal as a JSON string, which Druid can't plan as a
  # DECIMAL, so it is sent as a JSON number. Ecto pins datetime_add counts
  # as decimals.
  def to_db(%Decimal{} = value, _time_zone),
    do: db("DECIMAL", value |> Decimal.to_string(:normal) |> Jason.Fragment.new())

  def to_db(value, time_zone) when is_list(value),
    do: db("ARRAY", Enum.map(value, &to_db(&1, time_zone).value))

  defp db(type, value), do: %{type: type, value: value}

  @utc_zones ["UTC", "Etc/UTC", "GMT", "Etc/GMT", "Z"]

  # Zones that are a fixed offset from UTC in the tz database, so they don't
  # need a time zone database configured.
  @fixed_zones %{"EST" => -5 * 3600, "MST" => -7 * 3600, "HST" => -10 * 3600}

  defp session_time_zone(context) when is_map(context) do
    case Map.get(context, :sqlTimeZone) || Map.get(context, "sqlTimeZone") do
      zone when is_binary(zone) and zone not in @utc_zones -> zone
      _utc -> nil
    end
  end

  defp session_time_zone(_context), do: nil

  defp wall_clock(datetime, time_zone) do
    utc = DateTime.shift_zone!(datetime, "Etc/UTC")

    case fixed_offset(time_zone) do
      {:ok, seconds} -> utc |> DateTime.to_naive() |> NaiveDateTime.add(seconds)
      :error -> utc |> shift_zone!(time_zone) |> DateTime.to_naive()
    end
  end

  # Offsets such as "-05:00" or "-0500", and POSIX-style "Etc/GMT+5" zones,
  # whose sign is inverted
  defp fixed_offset(time_zone) do
    cond do
      seconds = @fixed_zones[time_zone] ->
        {:ok, seconds}

      match = Regex.run(~r/\A([+-])(\d{2}):?(\d{2})?\z/, time_zone) ->
        [_, sign, hours | minutes] = match
        {:ok, signed(sign, String.to_integer(hours) * 3600 + minutes_to_seconds(minutes))}

      match = Regex.run(~r/\AEtc\/GMT([+-])(\d{1,2})\z/, time_zone) ->
        [_, sign, hours] = match
        {:ok, -signed(sign, String.to_integer(hours) * 3600)}

      true ->
        :error
    end
  end

  defp minutes_to_seconds([minutes]), do: String.to_integer(minutes) * 60
  defp minutes_to_seconds([]), do: 0

  defp signed("+", seconds), do: seconds
  defp signed("-", seconds), do: -seconds

  defp shift_zone!(datetime, time_zone) do
    case DateTime.shift_zone(datetime, time_zone) do
      {:ok, shifted} ->
        shifted

      {:error, :utc_only_time_zone_database} ->
        raise ArgumentError,
              "sending a DateTime parameter with sqlTimeZone #{inspect(time_zone)} needs a " <>
                "time zone database. Add one such as :tz or :tzdata and set it with " <>
                "`config :elixir, :time_zone_database, ...`, or use a fixed offset such as " <>
                ~s("-05:00")

      {:error, reason} ->
        raise ArgumentError,
              "can't send a DateTime parameter with sqlTimeZone #{inspect(time_zone)}: " <>
                inspect(reason)
    end
  end
end
