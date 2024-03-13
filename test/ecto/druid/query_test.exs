defmodule Ecto.Druid.QueryTest do
  import Kernel,
    except: [abs: 1, ceil: 1, floor: 1, div: 2, length: 1, trunc: 1, round: 1, case: 2]

  alias Ecto.Adapters.Druid.TestRepo
  use ExUnit.Case
  import Ecto.Query
  import Ecto.Druid.Query

  defdelegate to_sql(query), to: TestRepo

  setup do
    start_supervised!(TestRepo, [])
    :ok
  end

  describe "keyword like functions" do
    test "distinct/1" do
      sql = from(t in "test", select: distinct(t.id)) |> to_sql()
      assert sql == {"SELECT DISTINCT t0.\"id\" FROM \"test\" AS t0", []}
    end

    test "interval/2" do
      sql = from("test", select: interval("1", "DAY")) |> to_sql()
      assert sql == {"SELECT INTERVAL '1' DAY FROM \"test\" AS t0", []}
    end
  end

  describe "numeric functions" do
    test "pi/0" do
      sql = from("test", select: pi()) |> to_sql()
      assert sql == {"SELECT PI() FROM \"test\" AS t0", []}
    end

    test "abs/1" do
      sql = from("test", select: abs(1)) |> to_sql()
      assert sql == {"SELECT ABS(1) FROM \"test\" AS t0", []}
    end

    test "ceil/1" do
      sql = from("test", select: ceil(1.1)) |> to_sql()
      assert sql == {"SELECT CEIL(1.1) FROM \"test\" AS t0", []}
    end

    test "exp/1" do
      sql = from("test", select: exp(1)) |> to_sql()
      assert sql == {"SELECT EXP(1) FROM \"test\" AS t0", []}
    end

    test "floor/1" do
      sql = from("test", select: floor(1.1)) |> to_sql()
      assert sql == {"SELECT FLOOR(1.1) FROM \"test\" AS t0", []}
    end

    test "ln/1" do
      sql = from("test", select: ln(1)) |> to_sql()
      assert sql == {"SELECT LN(1) FROM \"test\" AS t0", []}
    end

    test "log10/1" do
      sql = from("test", select: log10(1)) |> to_sql()
      assert sql == {"SELECT LOG10(1) FROM \"test\" AS t0", []}
    end

    test "power/2" do
      sql = from("test", select: power(2, 3)) |> to_sql()
      assert sql == {"SELECT POWER(2, 3) FROM \"test\" AS t0", []}
    end

    test "sqrt/1" do
      sql = from("test", select: sqrt(4)) |> to_sql()
      assert sql == {"SELECT SQRT(4) FROM \"test\" AS t0", []}
    end

    test "truncate/1" do
      sql = from("test", select: truncate(1.1)) |> to_sql()
      assert sql == {"SELECT TRUNCATE(1.1) FROM \"test\" AS t0", []}
    end

    test "truncate/2" do
      sql = from("test", select: truncate(1.1, 1)) |> to_sql()
      assert sql == {"SELECT TRUNCATE(1.1, 1) FROM \"test\" AS t0", []}
    end

    test "trunc/1" do
      sql = from("test", select: trunc(1.1)) |> to_sql()
      assert sql == {"SELECT TRUNC(1.1) FROM \"test\" AS t0", []}
    end

    test "trunc/2" do
      sql = from("test", select: trunc(1.1, 1)) |> to_sql()
      assert sql == {"SELECT TRUNC(1.1, 1) FROM \"test\" AS t0", []}
    end

    test "round/1" do
      sql = from("test", select: round(1.1)) |> to_sql()
      assert sql == {"SELECT ROUND(1.1) FROM \"test\" AS t0", []}
    end

    test "round/2" do
      sql = from("test", select: round(1.1, 1)) |> to_sql()
      assert sql == {"SELECT ROUND(1.1, 1) FROM \"test\" AS t0", []}
    end

    test "mod/2" do
      sql = from("test", select: mod(1, 2)) |> to_sql()
      assert sql == {"SELECT MOD(1, 2) FROM \"test\" AS t0", []}
    end

    test "sin/1" do
      sql = from("test", select: sin(1)) |> to_sql()
      assert sql == {"SELECT SIN(1) FROM \"test\" AS t0", []}
    end

    test "cos/1" do
      sql = from("test", select: cos(1)) |> to_sql()
      assert sql == {"SELECT COS(1) FROM \"test\" AS t0", []}
    end

    test "tan/1" do
      sql = from("test", select: tan(1)) |> to_sql()
      assert sql == {"SELECT TAN(1) FROM \"test\" AS t0", []}
    end

    test "cot/1" do
      sql = from("test", select: cot(1)) |> to_sql()
      assert sql == {"SELECT COT(1) FROM \"test\" AS t0", []}
    end

    test "asin/1" do
      sql = from("test", select: asin(1)) |> to_sql()
      assert sql == {"SELECT ASIN(1) FROM \"test\" AS t0", []}
    end

    test "acos/1" do
      sql = from("test", select: acos(1)) |> to_sql()
      assert sql == {"SELECT ACOS(1) FROM \"test\" AS t0", []}
    end

    test "atan/1" do
      sql = from("test", select: atan(1)) |> to_sql()
      assert sql == {"SELECT ATAN(1) FROM \"test\" AS t0", []}
    end

    test "atan2/2" do
      sql = from("test", select: atan2(1, 2)) |> to_sql()
      assert sql == {"SELECT ATAN2(1, 2) FROM \"test\" AS t0", []}
    end

    test "degrees/1" do
      sql = from("test", select: degrees(1)) |> to_sql()
      assert sql == {"SELECT DEGREES(1) FROM \"test\" AS t0", []}
    end

    test "radians/1" do
      sql = from("test", select: radians(1)) |> to_sql()
      assert sql == {"SELECT RADIANS(1) FROM \"test\" AS t0", []}
    end

    test "bitwise_and/2" do
      sql = from("test", select: bitwise_and(1, 2)) |> to_sql()
      assert sql == {"SELECT BITWISE_AND(1, 2) FROM \"test\" AS t0", []}
    end

    test "bitwise_complement/1" do
      sql = from("test", select: bitwise_complement(1)) |> to_sql()
      assert sql == {"SELECT BITWISE_COMPLEMENT(1) FROM \"test\" AS t0", []}
    end

    test "bitwise_convert_double_to_long_bits/1" do
      sql = from("test", select: bitwise_convert_double_to_long_bits(1)) |> to_sql()
      assert sql == {"SELECT BITWISE_CONVERT_DOUBLE_TO_LONG_BITS(1) FROM \"test\" AS t0", []}
    end

    test "bitwise_convert_long_bits_to_double/1" do
      sql = from("test", select: bitwise_convert_long_bits_to_double(1)) |> to_sql()
      assert sql == {"SELECT BITWISE_CONVERT_LONG_BITS_TO_DOUBLE(1) FROM \"test\" AS t0", []}
    end

    test "bitwise_or/2" do
      sql = from("test", select: bitwise_or(1, 2)) |> to_sql()
      assert sql == {"SELECT BITWISE_OR(1, 2) FROM \"test\" AS t0", []}
    end

    test "bitwise_shift_left/2" do
      sql = from("test", select: bitwise_shift_left(1, 2)) |> to_sql()
      assert sql == {"SELECT BITWISE_SHIFT_LEFT(1, 2) FROM \"test\" AS t0", []}
    end

    test "bitwise_shift_right/2" do
      sql = from("test", select: bitwise_shift_right(1, 2)) |> to_sql()
      assert sql == {"SELECT BITWISE_SHIFT_RIGHT(1, 2) FROM \"test\" AS t0", []}
    end

    test "bitwise_xor/2" do
      sql = from("test", select: bitwise_xor(1, 2)) |> to_sql()
      assert sql == {"SELECT BITWISE_XOR(1, 2) FROM \"test\" AS t0", []}
    end

    test "div/2" do
      sql = from("test", select: div(1, 2)) |> to_sql()
      assert sql == {"SELECT DIV(1, 2) FROM \"test\" AS t0", []}
    end

    test "human_readable_binary_byte_format/1" do
      sql = from("test", select: human_readable_binary_byte_format(1)) |> to_sql()
      assert sql == {"SELECT HUMAN_READABLE_BINARY_BYTE_FORMAT(1) FROM \"test\" AS t0", []}
    end

    test "human_readable_binary_byte_format/2" do
      sql = from("test", select: human_readable_binary_byte_format(1, 2)) |> to_sql()
      assert sql == {"SELECT HUMAN_READABLE_BINARY_BYTE_FORMAT(1, 2) FROM \"test\" AS t0", []}
    end

    test "human_readable_decimal_byte_format/1" do
      sql = from("test", select: human_readable_decimal_byte_format(1)) |> to_sql()
      assert sql == {"SELECT HUMAN_READABLE_DECIMAL_BYTE_FORMAT(1) FROM \"test\" AS t0", []}
    end

    test "human_readable_decimal_byte_format/2" do
      sql = from("test", select: human_readable_decimal_byte_format(1, 2)) |> to_sql()
      assert sql == {"SELECT HUMAN_READABLE_DECIMAL_BYTE_FORMAT(1, 2) FROM \"test\" AS t0", []}
    end

    test "human_readable_decimal_format/2" do
      sql = from("test", select: human_readable_decimal_format(1, 2)) |> to_sql()
      assert sql == {"SELECT HUMAN_READABLE_DECIMAL_FORMAT(1, 2) FROM \"test\" AS t0", []}
    end

    test "safe_divide/2" do
      sql = from("test", select: safe_divide(1, 2)) |> to_sql()
      assert sql == {"SELECT SAFE_DIVIDE(1, 2) FROM \"test\" AS t0", []}
    end
  end

  describe "string functions" do
    test "concat/1" do
      sql = from("test", select: concat(["a", "b"])) |> to_sql()
      assert sql == {"SELECT CONCAT('a', 'b') FROM \"test\" AS t0", []}
    end

    test "textcat/2" do
      sql = from("test", select: textcat("a", "b")) |> to_sql()
      assert sql == {"SELECT TEXTCAT('a', 'b') FROM \"test\" AS t0", []}
    end

    test "contains_string/2" do
      sql = from("test", select: contains_string("a", "b")) |> to_sql()
      assert sql == {"SELECT CONTAINS_STRING('a', 'b') FROM \"test\" AS t0", []}
    end

    test "icontains_string/2" do
      sql = from("test", select: icontains_string("a", "b")) |> to_sql()
      assert sql == {"SELECT ICONTAINS_STRING('a', 'b') FROM \"test\" AS t0", []}
    end

    test "decode_base64_utf8/1" do
      sql = from("test", select: decode_base64_utf8("a")) |> to_sql()
      assert sql == {"SELECT DECODE_BASE64_UTF8('a') FROM \"test\" AS t0", []}
    end

    test "left/1" do
      sql = from("test", select: left("a")) |> to_sql()
      assert sql == {"SELECT LEFT('a') FROM \"test\" AS t0", []}
    end

    test "left/2" do
      sql = from("test", select: left("a", 1)) |> to_sql()
      assert sql == {"SELECT LEFT('a', 1) FROM \"test\" AS t0", []}
    end

    test "right/1" do
      sql = from("test", select: right("a")) |> to_sql()
      assert sql == {"SELECT RIGHT('a') FROM \"test\" AS t0", []}
    end

    test "right/2" do
      sql = from("test", select: right("a", 1)) |> to_sql()
      assert sql == {"SELECT RIGHT('a', 1) FROM \"test\" AS t0", []}
    end

    test "length/1" do
      sql = from("test", select: length("a")) |> to_sql()
      assert sql == {"SELECT LENGTH('a') FROM \"test\" AS t0", []}
    end

    test "char_length/1" do
      sql = from("test", select: char_length("a")) |> to_sql()
      assert sql == {"SELECT CHAR_LENGTH('a') FROM \"test\" AS t0", []}
    end

    test "character_length/1" do
      sql = from("test", select: character_length("a")) |> to_sql()
      assert sql == {"SELECT CHARACTER_LENGTH('a') FROM \"test\" AS t0", []}
    end

    test "strlen/1" do
      sql = from("test", select: strlen("a")) |> to_sql()
      assert sql == {"SELECT STRLEN('a') FROM \"test\" AS t0", []}
    end

    test "lookup/2" do
      sql = from("test", select: lookup("a", "b")) |> to_sql()
      assert sql == {"SELECT LOOKUP('a', 'b') FROM \"test\" AS t0", []}
    end

    test "lookup/3" do
      sql = from("test", select: lookup("a", "b", "c")) |> to_sql()
      assert sql == {"SELECT LOOKUP('a', 'b', 'c') FROM \"test\" AS t0", []}
    end

    test "lower/1" do
      sql = from("test", select: lower("a")) |> to_sql()
      assert sql == {"SELECT LOWER('a') FROM \"test\" AS t0", []}
    end

    test "upper/1" do
      sql = from("test", select: upper("a")) |> to_sql()
      assert sql == {"SELECT UPPER('a') FROM \"test\" AS t0", []}
    end

    test "lpad/2" do
      sql = from("test", select: lpad("a", 1)) |> to_sql()
      assert sql == {"SELECT LPAD('a', 1) FROM \"test\" AS t0", []}
    end

    test "lpad/3" do
      sql = from("test", select: lpad("a", 1, "c")) |> to_sql()
      assert sql == {"SELECT LPAD('a', 1, 'c') FROM \"test\" AS t0", []}
    end

    test "rpad/2" do
      sql = from("test", select: rpad("a", 1)) |> to_sql()
      assert sql == {"SELECT RPAD('a', 1) FROM \"test\" AS t0", []}
    end

    test "rpad/3" do
      sql = from("test", select: rpad("a", 1, "c")) |> to_sql()
      assert sql == {"SELECT RPAD('a', 1, 'c') FROM \"test\" AS t0", []}
    end

    test "parse_long/1" do
      sql = from("test", select: parse_long("1")) |> to_sql()
      assert sql == {"SELECT PARSE_LONG('1') FROM \"test\" AS t0", []}
    end

    test "parse_long/2" do
      sql = from("test", select: parse_long("1", 10)) |> to_sql()
      assert sql == {"SELECT PARSE_LONG('1', 10) FROM \"test\" AS t0", []}
    end

    test "position/2" do
      sql = from("test", select: position("a", "b")) |> to_sql()
      assert sql == {"SELECT POSITION('a' IN 'b') FROM \"test\" AS t0", []}
    end

    test "position/3" do
      sql = from("test", select: position("a", "b", 0)) |> to_sql()
      assert sql == {"SELECT POSITION('a' IN 'b' FROM 0) FROM \"test\" AS t0", []}
    end

    test "regexp_extract/2" do
      sql = from("test", select: regexp_extract("a", "b")) |> to_sql()
      assert sql == {"SELECT REGEXP_EXTRACT('a', 'b') FROM \"test\" AS t0", []}
    end

    test "regexp_extract/3" do
      sql = from("test", select: regexp_extract("a", "b", 0)) |> to_sql()
      assert sql == {"SELECT REGEXP_EXTRACT('a', 'b', 0) FROM \"test\" AS t0", []}
    end

    test "regexp_like/2" do
      sql = from("test", select: regexp_like("a", "b")) |> to_sql()
      assert sql == {"SELECT REGEXP_LIKE('a', 'b') FROM \"test\" AS t0", []}
    end

    test "regexp_replace/3" do
      sql = from("test", select: regexp_replace("a", "b", 0)) |> to_sql()
      assert sql == {"SELECT REGEXP_REPLACE('a', 'b', 0) FROM \"test\" AS t0", []}
    end

    test "replace/3" do
      sql = from("test", select: replace("a", "b", 0)) |> to_sql()
      assert sql == {"SELECT REPLACE('a', 'b', 0) FROM \"test\" AS t0", []}
    end

    test "repeat/2" do
      sql = from("test", select: repeat("a", 1)) |> to_sql()
      assert sql == {"SELECT REPEAT('a', 1) FROM \"test\" AS t0", []}
    end

    test "reverse/1" do
      sql = from("test", select: reverse("a")) |> to_sql()
      assert sql == {"SELECT REVERSE('a') FROM \"test\" AS t0", []}
    end

    test "string_format/2" do
      sql = from("test", select: string_format("a", "b")) |> to_sql()
      assert sql == {"SELECT STRING_FORMAT('a', 'b') FROM \"test\" AS t0", []}

      sql = from("test", select: string_format("a", ["b", "c"])) |> to_sql()
      assert sql == {"SELECT STRING_FORMAT('a', 'b', 'c') FROM \"test\" AS t0", []}
    end

    test "strpos/2" do
      sql = from("test", select: strpos("a", "b")) |> to_sql()
      assert sql == {"SELECT STRPOS('a', 'b') FROM \"test\" AS t0", []}
    end

    test "substring/2" do
      sql = from("test", select: substring("a", 1)) |> to_sql()
      assert sql == {"SELECT SUBSTRING('a', 1) FROM \"test\" AS t0", []}
    end

    test "substring/3" do
      sql = from("test", select: substring("a", 1, 2)) |> to_sql()
      assert sql == {"SELECT SUBSTRING('a', 1, 2) FROM \"test\" AS t0", []}
    end

    test "substr/2" do
      sql = from("test", select: substr("a", 1)) |> to_sql()
      assert sql == {"SELECT SUBSTR('a', 1) FROM \"test\" AS t0", []}
    end

    test "substr/3" do
      sql = from("test", select: substr("a", 1, 2)) |> to_sql()
      assert sql == {"SELECT SUBSTR('a', 1, 2) FROM \"test\" AS t0", []}
    end

    test "trim/1" do
      sql = from("test", select: trim("a")) |> to_sql()
      assert sql == {"SELECT TRIM('a') FROM \"test\" AS t0", []}
    end

    test "trim/2" do
      sql = from("test", select: trim(" ", "a")) |> to_sql()
      assert sql == {"SELECT TRIM(' ' FROM 'a') FROM \"test\" AS t0", []}
    end

    test "btrim/1" do
      sql = from("test", select: btrim("a")) |> to_sql()
      assert sql == {"SELECT BTRIM('a') FROM \"test\" AS t0", []}
    end

    test "btrim/2" do
      sql = from("test", select: btrim("a", " ")) |> to_sql()
      assert sql == {"SELECT BTRIM('a', ' ') FROM \"test\" AS t0", []}
    end

    test "ltrim/1" do
      sql = from("test", select: ltrim("a")) |> to_sql()
      assert sql == {"SELECT LTRIM('a') FROM \"test\" AS t0", []}
    end

    test "ltrim/2" do
      sql = from("test", select: ltrim("a", " ")) |> to_sql()
      assert sql == {"SELECT LTRIM('a', ' ') FROM \"test\" AS t0", []}
    end

    test "rtrim/1" do
      sql = from("test", select: rtrim("a")) |> to_sql()
      assert sql == {"SELECT RTRIM('a') FROM \"test\" AS t0", []}
    end

    test "rtrim/2" do
      sql = from("test", select: rtrim("a", " ")) |> to_sql()
      assert sql == {"SELECT RTRIM('a', ' ') FROM \"test\" AS t0", []}
    end
  end

  describe "date and time functions" do
    test "current_timestamp/0" do
      sql = from("test", select: current_timestamp()) |> to_sql()
      assert sql == {"SELECT CURRENT_TIMESTAMP() FROM \"test\" AS t0", []}
    end

    test "current_date/0" do
      sql = from("test", select: current_date()) |> to_sql()
      assert sql == {"SELECT CURRENT_DATE() FROM \"test\" AS t0", []}
    end

    test "date_trunc/2" do
      sql = from(t in "test", select: date_trunc("day", t.time)) |> to_sql()
      assert sql == {"SELECT DATE_TRUNC('day', t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "time_ceil/2" do
      sql = from(t in "test", select: time_ceil(t.time, "PT1H")) |> to_sql()
      assert sql == {"SELECT TIME_CEIL(t0.\"time\", 'PT1H') FROM \"test\" AS t0", []}
    end

    test "time_ceil/3" do
      sql =
        from(t in "test", select: time_ceil(t.time, "PT1H", "1970-01-01T00:00:00")) |> to_sql()

      assert sql ==
               {"SELECT TIME_CEIL(t0.\"time\", 'PT1H', '1970-01-01T00:00:00') FROM \"test\" AS t0",
                []}
    end

    test "time_ceil/4" do
      sql =
        from(t in "test",
          select: time_ceil(t.time, "PT1H", "1970-01-01T00:00:00", "America/Los_Angeles")
        )
        |> to_sql()

      assert sql ==
               {"SELECT TIME_CEIL(t0.\"time\", 'PT1H', '1970-01-01T00:00:00', 'America/Los_Angeles') FROM \"test\" AS t0",
                []}
    end

    test "time_floor/2" do
      sql = from(t in "test", select: time_floor(t.time, "PT1H")) |> to_sql()
      assert sql == {"SELECT TIME_FLOOR(t0.\"time\", 'PT1H') FROM \"test\" AS t0", []}
    end

    test "time_floor/3" do
      sql =
        from(t in "test", select: time_floor(t.time, "PT1H", "1970-01-01T00:00:00")) |> to_sql()

      assert sql ==
               {"SELECT TIME_FLOOR(t0.\"time\", 'PT1H', '1970-01-01T00:00:00') FROM \"test\" AS t0",
                []}
    end

    test "time_floor/4" do
      sql =
        from(t in "test",
          select: time_floor(t.time, "PT1H", "1970-01-01T00:00:00", "America/Los_Angeles")
        )
        |> to_sql()

      assert sql ==
               {"SELECT TIME_FLOOR(t0.\"time\", 'PT1H', '1970-01-01T00:00:00', 'America/Los_Angeles') FROM \"test\" AS t0",
                []}
    end

    test "time_shift/3" do
      sql = from(t in "test", select: time_shift(t.time, "P1D", 1)) |> to_sql()
      assert sql == {"SELECT TIME_SHIFT(t0.\"time\", 'P1D', 1) FROM \"test\" AS t0", []}
    end

    test "time_shift/4" do
      sql =
        from(t in "test", select: time_shift(t.time, "P1D", 1, "America/Los_Angeles")) |> to_sql()

      assert sql ==
               {"SELECT TIME_SHIFT(t0.\"time\", 'P1D', 1, 'America/Los_Angeles') FROM \"test\" AS t0",
                []}
    end

    test "time_extract/2" do
      sql = from(t in "test", select: time_extract(t.time, "EPOCH")) |> to_sql()
      assert sql == {"SELECT TIME_EXTRACT(t0.\"time\", 'EPOCH') FROM \"test\" AS t0", []}
    end

    test "time_extract/3" do
      sql =
        from(t in "test", select: time_extract(t.time, "EPOCH", "America/Los_Angeles"))
        |> to_sql()

      assert sql ==
               {"SELECT TIME_EXTRACT(t0.\"time\", 'EPOCH', 'America/Los_Angeles') FROM \"test\" AS t0",
                []}
    end

    test "time_parse/1" do
      sql = from("test", select: time_parse("2000-02-01 00:00:00")) |> to_sql()
      assert sql == {"SELECT TIME_PARSE('2000-02-01 00:00:00') FROM \"test\" AS t0", []}
    end

    test "time_parse/2" do
      sql =
        from("test", select: time_parse("2000-02-01 00:00:00", "MMMM, yyyy")) |> to_sql()

      assert sql ==
               {"SELECT TIME_PARSE('2000-02-01 00:00:00', 'MMMM, yyyy') FROM \"test\" AS t0", []}
    end

    test "time_parse/3" do
      sql =
        from("test",
          select: time_parse("2000-02-01 00:00:00", "MMMM, yyyy", "America/Los_Angeles")
        )
        |> to_sql()

      assert sql ==
               {"SELECT TIME_PARSE('2000-02-01 00:00:00', 'MMMM, yyyy', 'America/Los_Angeles') FROM \"test\" AS t0",
                []}
    end

    test "time_in_interval/2" do
      sql =
        from(t in "test", select: time_in_interval(t.time, "2000-01-01/2000-02-01")) |> to_sql()

      assert sql ==
               {"SELECT TIME_IN_INTERVAL(t0.\"time\", '2000-01-01/2000-02-01') FROM \"test\" AS t0",
                []}
    end

    test "millis_to_timestamp/1" do
      sql = from("test", select: millis_to_timestamp(1)) |> to_sql()
      assert sql == {"SELECT MILLIS_TO_TIMESTAMP(1) FROM \"test\" AS t0", []}
    end

    test "timestamp_to_millis/1" do
      sql = from(t in "test", select: timestamp_to_millis(t.time)) |> to_sql()
      assert sql == {"SELECT TIMESTAMP_TO_MILLIS(t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "extract/2" do
      sql = from(t in "test", select: extract("DAY", t.time)) |> to_sql()
      assert sql == {"SELECT EXTRACT(DAY FROM t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "floor/2" do
      sql = from(t in "test", select: floor(t.time, "DAY")) |> to_sql()
      assert sql == {"SELECT FLOOR(t0.\"time\" TO DAY) FROM \"test\" AS t0", []}
    end

    test "ceil/2" do
      sql = from(t in "test", select: ceil(t.time, "DAY")) |> to_sql()
      assert sql == {"SELECT CEIL(t0.\"time\" TO DAY) FROM \"test\" AS t0", []}
    end

    test "timestampadd/3" do
      sql = from(t in "test", select: timestampadd("DAY", 1, t.time)) |> to_sql()
      assert sql == {"SELECT TIMESTAMPADD(DAY, 1, t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "timestampdiff/3" do
      sql = from(t in "test", select: timestampdiff("DAY", t.time, t.time)) |> to_sql()

      assert sql ==
               {"SELECT TIMESTAMPDIFF(DAY, t0.\"time\", t0.\"time\") FROM \"test\" AS t0", []}
    end
  end

  describe "reduction functions" do
    test "greatest/1" do
      sql = from("test", select: greatest([1, 2, 3])) |> to_sql()
      assert sql == {"SELECT GREATEST(1, 2, 3) FROM \"test\" AS t0", []}
    end

    test "least/1" do
      sql = from("test", select: least([1, 2, 3])) |> to_sql()
      assert sql == {"SELECT LEAST(1, 2, 3) FROM \"test\" AS t0", []}
    end
  end

  describe "ip address functions" do
    test "ipv4_match/2" do
      sql = from("test", select: ipv4_match("127.0.0.1", "127.0.0.0/16")) |> to_sql()
      assert sql == {"SELECT IPV4_MATCH('127.0.0.1', '127.0.0.0/16') FROM \"test\" AS t0", []}
    end

    test "ipv4_parse/1" do
      sql = from("test", select: ipv4_parse("127.0.0.1")) |> to_sql()
      assert sql == {"SELECT IPV4_PARSE('127.0.0.1') FROM \"test\" AS t0", []}
    end

    test "ipv4_stringify/1" do
      sql = from("test", select: ipv4_stringify(2_130_706_433)) |> to_sql()
      assert sql == {"SELECT IPV4_STRINGIFY(2130706433) FROM \"test\" AS t0", []}
    end

    test "ipv6_match/2" do
      sql =
        from("test", select: ipv6_match("75e9:efa4:29c6:85f6::232c", "75e9:efa4:29c6:85f6::/64"))
        |> to_sql()

      assert sql ==
               {"SELECT IPV6_MATCH('75e9:efa4:29c6:85f6::232c', '75e9:efa4:29c6:85f6::/64') FROM \"test\" AS t0",
                []}
    end
  end

  describe "hll sketch functions" do
    test "hll_sketch_estimate/1" do
      sql = from(t in "test", select: hll_sketch_estimate(t.sketch)) |> to_sql()
      assert sql == {"SELECT HLL_SKETCH_ESTIMATE(t0.\"sketch\") FROM \"test\" AS t0", []}
    end

    test "hll_sketch_estimate/2" do
      sql = from(t in "test", select: hll_sketch_estimate(t.sketch, true)) |> to_sql()
      assert sql == {"SELECT HLL_SKETCH_ESTIMATE(t0.\"sketch\", TRUE) FROM \"test\" AS t0", []}
    end

    test "hll_sketch_estimate_with_error_bounds/1" do
      sql = from(t in "test", select: hll_sketch_estimate_with_error_bounds(t.sketch)) |> to_sql()

      assert sql ==
               {"SELECT HLL_SKETCH_ESTIMATE_WITH_ERROR_BOUNDS(t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "hll_sketch_estimate_with_error_bounds/2" do
      sql =
        from(t in "test", select: hll_sketch_estimate_with_error_bounds(t.sketch, 2)) |> to_sql()

      assert sql ==
               {"SELECT HLL_SKETCH_ESTIMATE_WITH_ERROR_BOUNDS(t0.\"sketch\", 2) FROM \"test\" AS t0",
                []}
    end

    test "hll_sketch_union/1" do
      sql = from(t in "test", select: hll_sketch_union([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT HLL_SKETCH_UNION(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0", []}
    end

    test "hll_sketch_union/3" do
      sql =
        from(t in "test", select: hll_sketch_union(12, "HLL_8", [t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT HLL_SKETCH_UNION(12, 'HLL_8', t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "hll_sketch_to_string/1" do
      sql = from(t in "test", select: hll_sketch_to_string(t.sketch)) |> to_sql()
      assert sql == {"SELECT HLL_SKETCH_TO_STRING(t0.\"sketch\") FROM \"test\" AS t0", []}
    end
  end

  describe "theta sketch functions" do
    test "theta_sketch_estimate/1" do
      sql = from(t in "test", select: theta_sketch_estimate(t.sketch)) |> to_sql()
      assert sql == {"SELECT THETA_SKETCH_ESTIMATE(t0.\"sketch\") FROM \"test\" AS t0", []}
    end

    test "theta_sketch_estimate_with_error_bounds/1" do
      sql =
        from(t in "test", select: theta_sketch_estimate_with_error_bounds(t.sketch, 2))
        |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_ESTIMATE_WITH_ERROR_BOUNDS(t0.\"sketch\", 2) FROM \"test\" AS t0",
                []}
    end

    test "theta_sketch_union/1" do
      sql = from(t in "test", select: theta_sketch_union([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_UNION(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0", []}
    end

    test "theta_sketch_union/2" do
      sql = from(t in "test", select: theta_sketch_union(256, [t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_UNION(256, t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "theta_sketch_intersect/1" do
      sql = from(t in "test", select: theta_sketch_intersect([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_INTERSECT(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "theta_sketch_intersect/2" do
      sql =
        from(t in "test", select: theta_sketch_intersect(256, [t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_INTERSECT(256, t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "theta_sketch_not/1" do
      sql = from(t in "test", select: theta_sketch_not([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_NOT(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0", []}
    end

    test "theta_sketch_not/2" do
      sql = from(t in "test", select: theta_sketch_not(256, [t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT THETA_SKETCH_NOT(256, t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end
  end

  describe "Quantiles sketch functions" do
    test "ds_get_quantile/2" do
      sql = from(t in "test", select: ds_get_quantile(t.sketch, 0.5)) |> to_sql()
      assert sql == {"SELECT DS_GET_QUANTILE(t0.\"sketch\", 0.5) FROM \"test\" AS t0", []}
    end

    test "ds_get_quantiles/2" do
      sql = from(t in "test", select: ds_get_quantiles(t.sketch, [0.5, 0.75])) |> to_sql()
      assert sql == {"SELECT DS_GET_QUANTILES(t0.\"sketch\", 0.5, 0.75) FROM \"test\" AS t0", []}
    end

    test "ds_histogram/2" do
      sql = from(t in "test", select: ds_histogram(t.sketch, [0.5, 0.75])) |> to_sql()
      assert sql == {"SELECT DS_HISTOGRAM(t0.\"sketch\", 0.5, 0.75) FROM \"test\" AS t0", []}
    end

    test "ds_cdf/2" do
      sql = from(t in "test", select: ds_cdf(t.sketch, [0.5, 0.75])) |> to_sql()
      assert sql == {"SELECT DS_CDF(t0.\"sketch\", 0.5, 0.75) FROM \"test\" AS t0", []}
    end

    test "ds_rank/2" do
      sql = from(t in "test", select: ds_rank(t.sketch, 0.5)) |> to_sql()
      assert sql == {"SELECT DS_RANK(t0.\"sketch\", 0.5) FROM \"test\" AS t0", []}
    end

    test "ds_quantile_summary/1" do
      sql = from(t in "test", select: ds_quantile_summary(t.sketch)) |> to_sql()
      assert sql == {"SELECT DS_QUANTILE_SUMMARY(t0.\"sketch\") FROM \"test\" AS t0", []}
    end
  end

  describe "Tuple sketch functions" do
    test "ds_tuple_doubles_metrics_sum_estimate/1" do
      sql = from(t in "test", select: ds_tuple_doubles_metrics_sum_estimate(t.sketch)) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_METRICS_SUM_ESTIMATE(t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_intersect/1" do
      sql =
        from(t in "test", select: ds_tuple_doubles_intersect([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_INTERSECT(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_intersect/2" do
      sql =
        from(t in "test", select: ds_tuple_doubles_intersect([t.sketch, t.sketch], 2)) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_INTERSECT(t0.\"sketch\", t0.\"sketch\", 2) FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_not/1" do
      sql = from(t in "test", select: ds_tuple_doubles_not([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_NOT(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_not/2" do
      sql = from(t in "test", select: ds_tuple_doubles_not([t.sketch, t.sketch], 2)) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_NOT(t0.\"sketch\", t0.\"sketch\", 2) FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_union/1" do
      sql = from(t in "test", select: ds_tuple_doubles_union([t.sketch, t.sketch])) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_UNION(t0.\"sketch\", t0.\"sketch\") FROM \"test\" AS t0",
                []}
    end

    test "ds_tuple_doubles_union/2" do
      sql = from(t in "test", select: ds_tuple_doubles_union([t.sketch, t.sketch], 2)) |> to_sql()

      assert sql ==
               {"SELECT DS_TUPLE_DOUBLES_UNION(t0.\"sketch\", t0.\"sketch\", 2) FROM \"test\" AS t0",
                []}
    end
  end

  describe "Other scaler functions" do
    test "bloom_filter_test/2" do
      sql = from("test", select: bloom_filter_test("a", "b")) |> to_sql()
      assert sql == {"SELECT BLOOM_FILTER_TEST('a', 'b') FROM \"test\" AS t0", []}
    end

    test "sql_case/2" do
      sql = from("test", select: sql_case("a", when: "a", then: true, else: false)) |> to_sql()

      assert sql ==
               {"SELECT CASE 'a' WHEN 'a' THEN TRUE ELSE FALSE END FROM \"test\" AS t0", []}
    end

    test "sql_case/1" do
      sql =
        from("test", select: sql_case(when: 1 == 1, then: true, else: false))
        |> to_sql()

      assert sql ==
               {"SELECT CASE WHEN 1 = 1 THEN TRUE ELSE FALSE END FROM \"test\" AS t0", []}
    end

    test "coalesce/1" do
      sql = from("test", select: coalesce(["value1", "value2"])) |> to_sql()
      assert sql == {"SELECT COALESCE('value1', 'value2') FROM \"test\" AS t0", []}
    end

    test "decode_base64_complex/2" do
      sql = from("test", select: decode_base64_complex("dataType", "expr")) |> to_sql()
      assert sql == {"SELECT DECODE_BASE64_COMPLEX('dataType', 'expr') FROM \"test\" AS t0", []}
    end

    test "nullif/2" do
      sql = from("test", select: nullif("value1", "value2")) |> to_sql()
      assert sql == {"SELECT NULLIF('value1', 'value2') FROM \"test\" AS t0", []}
    end

    test "nvl/2" do
      sql = from("test", select: nvl("value1", "value2")) |> to_sql()
      assert sql == {"SELECT NVL('value1', 'value2') FROM \"test\" AS t0", []}
    end
  end

  describe "general aggregate functions" do
    test "approx_count_distinct/1" do
      sql = from(t in "test", select: approx_count_distinct(t.category)) |> to_sql()
      assert sql == {"SELECT APPROX_COUNT_DISTINCT(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "approx_count_distinct_builtin/1" do
      sql = from(t in "test", select: approx_count_distinct_builtin(t.category)) |> to_sql()

      assert sql ==
               {"SELECT APPROX_COUNT_DISTINCT_BUILTIN(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "approx_quantile/2" do
      sql = from(t in "test", select: approx_quantile(t.category, 0.5)) |> to_sql()
      assert sql == {"SELECT APPROX_QUANTILE(t0.\"category\", 0.5) FROM \"test\" AS t0", []}
    end

    test "approx_quantile_fixed_buckets/5" do
      sql =
        from(t in "test", select: approx_quantile_fixed_buckets(t.category, 0.5, 10, 0, 100))
        |> to_sql()

      assert sql ==
               {"SELECT APPROX_QUANTILE_FIXED_BUCKETS(t0.\"category\", 0.5, 10, 0, 100) FROM \"test\" AS t0",
                []}
    end

    test "bloom_filter/2" do
      sql = from(t in "test", select: bloom_filter(t.category, 100)) |> to_sql()
      assert sql == {"SELECT BLOOM_FILTER(t0.\"category\", 100) FROM \"test\" AS t0", []}
    end

    test "var_pop/1" do
      sql = from(t in "test", select: var_pop(t.category)) |> to_sql()
      assert sql == {"SELECT VAR_POP(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "var_samp/1" do
      sql = from(t in "test", select: var_samp(t.category)) |> to_sql()
      assert sql == {"SELECT VAR_SAMP(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "variance/1" do
      sql = from(t in "test", select: variance(t.category)) |> to_sql()
      assert sql == {"SELECT VARIANCE(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "stddev_pop/1" do
      sql = from(t in "test", select: stddev_pop(t.category)) |> to_sql()
      assert sql == {"SELECT STDDEV_POP(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "stddev_samp/1" do
      sql = from(t in "test", select: stddev_samp(t.category)) |> to_sql()
      assert sql == {"SELECT STDDEV_SAMP(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "stddev/1" do
      sql = from(t in "test", select: stddev(t.category)) |> to_sql()
      assert sql == {"SELECT STDDEV(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "earliest/1" do
      sql = from(t in "test", select: earliest(t.category)) |> to_sql()
      assert sql == {"SELECT EARLIEST(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "earliest/2" do
      sql = from(t in "test", select: earliest(t.category, 100)) |> to_sql()
      assert sql == {"SELECT EARLIEST(t0.\"category\", 100) FROM \"test\" AS t0", []}
    end

    test "earliest_by/2" do
      sql = from(t in "test", select: earliest_by(t.category, t.time)) |> to_sql()
      assert sql == {"SELECT EARLIEST_BY(t0.\"category\", t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "earliest_by/3" do
      sql = from(t in "test", select: earliest_by(t.category, t.time, 100)) |> to_sql()

      assert sql ==
               {"SELECT EARLIEST_BY(t0.\"category\", t0.\"time\", 100) FROM \"test\" AS t0", []}
    end

    test "latest/1" do
      sql = from(t in "test", select: latest(t.category)) |> to_sql()
      assert sql == {"SELECT LATEST(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "latest/2" do
      sql = from(t in "test", select: latest(t.category, 100)) |> to_sql()
      assert sql == {"SELECT LATEST(t0.\"category\", 100) FROM \"test\" AS t0", []}
    end

    test "latest_by/2" do
      sql = from(t in "test", select: latest_by(t.category, t.time)) |> to_sql()
      assert sql == {"SELECT LATEST_BY(t0.\"category\", t0.\"time\") FROM \"test\" AS t0", []}
    end

    test "latest_by/3" do
      sql = from(t in "test", select: latest_by(t.category, t.time, 100)) |> to_sql()

      assert sql ==
               {"SELECT LATEST_BY(t0.\"category\", t0.\"time\", 100) FROM \"test\" AS t0", []}
    end

    test "any_value/1" do
      sql = from(t in "test", select: any_value(t.category)) |> to_sql()
      assert sql == {"SELECT ANY_VALUE(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "any_value/2" do
      sql = from(t in "test", select: any_value(t.category, 100)) |> to_sql()
      assert sql == {"SELECT ANY_VALUE(t0.\"category\", 100) FROM \"test\" AS t0", []}
    end

    test "any_value/3" do
      sql =
        from(t in "test", select: any_value(t.category, 100, true)) |> to_sql()

      assert sql ==
               {"SELECT ANY_VALUE(t0.\"category\", 100, TRUE) FROM \"test\" AS t0", []}
    end

    test "grouping/1" do
      sql = from(t in "test", select: grouping([t.time, t.category])) |> to_sql()
      assert sql == {"SELECT GROUPING(t0.\"time\", t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "array_agg/1" do
      sql = from(t in "test", select: array_agg(t.category)) |> to_sql()
      assert sql == {"SELECT ARRAY_AGG(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "array_agg/1 distinct" do
      sql = from(t in "test", select: array_agg(distinct(t.category))) |> to_sql()
      assert sql == {"SELECT ARRAY_AGG(DISTINCT t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "array_agg/2" do
      sql = from(t in "test", select: array_agg(t.category, 40)) |> to_sql()
      assert sql == {"SELECT ARRAY_AGG(t0.\"category\", 40) FROM \"test\" AS t0", []}
    end

    test "array_concat_agg/1" do
      sql = from(t in "test", select: array_concat_agg(t.category)) |> to_sql()
      assert sql == {"SELECT ARRAY_CONCAT_AGG(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "array_concat_agg/1 distinct" do
      sql = from(t in "test", select: array_concat_agg(distinct(t.category))) |> to_sql()
      assert sql == {"SELECT ARRAY_CONCAT_AGG(DISTINCT t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "array_concat_agg/2" do
      sql = from(t in "test", select: array_concat_agg(t.category, 40)) |> to_sql()
      assert sql == {"SELECT ARRAY_CONCAT_AGG(t0.\"category\", 40) FROM \"test\" AS t0", []}
    end

    test "string_agg/1" do
      sql = from(t in "test", select: string_agg(t.category)) |> to_sql()
      assert sql == {"SELECT STRING_AGG(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "string_agg/1 distinct" do
      sql = from(t in "test", select: string_agg(distinct(t.category))) |> to_sql()
      assert sql == {"SELECT STRING_AGG(DISTINCT t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "string_agg/2" do
      sql = from(t in "test", select: string_agg(t.category, ",")) |> to_sql()
      assert sql == {"SELECT STRING_AGG(t0.\"category\", ',') FROM \"test\" AS t0", []}
    end

    test "string_agg/3" do
      sql = from(t in "test", select: string_agg(t.category, ",", 40)) |> to_sql()
      assert sql == {"SELECT STRING_AGG(t0.\"category\", ',', 40) FROM \"test\" AS t0", []}
    end

    test "listagg/1" do
      sql = from(t in "test", select: listagg(t.category)) |> to_sql()
      assert sql == {"SELECT LISTAGG(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "listagg/1 distinct" do
      sql = from(t in "test", select: listagg(distinct(t.category))) |> to_sql()
      assert sql == {"SELECT LISTAGG(DISTINCT t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "listagg/2" do
      sql = from(t in "test", select: listagg(t.category, ",")) |> to_sql()
      assert sql == {"SELECT LISTAGG(t0.\"category\", ',') FROM \"test\" AS t0", []}
    end

    test "listagg/3" do
      sql = from(t in "test", select: listagg(t.category, ",", 40)) |> to_sql()
      assert sql == {"SELECT LISTAGG(t0.\"category\", ',', 40) FROM \"test\" AS t0", []}
    end

    test "bit_and/1" do
      sql = from(t in "test", select: bit_and(t.category)) |> to_sql()
      assert sql == {"SELECT BIT_AND(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "bit_or/1" do
      sql = from(t in "test", select: bit_or(t.category)) |> to_sql()
      assert sql == {"SELECT BIT_OR(t0.\"category\") FROM \"test\" AS t0", []}
    end

    test "bit_xor/1" do
      sql = from(t in "test", select: bit_xor(t.category)) |> to_sql()
      assert sql == {"SELECT BIT_XOR(t0.\"category\") FROM \"test\" AS t0", []}
    end
  end
end
