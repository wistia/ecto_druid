defmodule Ecto.Druid.QueryTest do
  import Kernel, except: [abs: 1, ceil: 1, floor: 1, div: 2, length: 1, trunc: 1, round: 1]
  alias Ecto.Adapters.Druid.TestRepo
  use ExUnit.Case
  import Ecto.Query
  import Ecto.Druid.Query

  defdelegate to_sql(query), to: TestRepo

  setup do
    start_supervised!(TestRepo, [])
    :ok
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
end

# Function	Notes
# IPV4_MATCH(address, subnet)	Returns true if the address belongs to the subnet literal, else false. If address is not a valid IPv4 address, then false is returned. This function is more efficient if address is an integer instead of a string.
# IPV4_PARSE(address)	Parses address into an IPv4 address stored as an integer . If address is an integer that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address.
# IPV4_STRINGIFY(address)	Converts address into an IPv4 address dotted-decimal string. If address is a string that is a valid IPv4 address, then it is passed through. Returns null if address cannot be represented as an IPv4 address.
# IPV6_MATCH(address, subnet)	Returns 1 if the IPv6 address belongs to the subnet literal, else 0. If address is not a valid IPv6 address, then 0 is returned.
