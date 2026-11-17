defmodule Ecto.Druid.Native.ExpressionTest do
  use ExUnit.Case, async: true

  import Ecto.Druid.Native.Expression
  alias Ecto.Druid.Native.Expression

  doctest Ecto.Druid.Native.Expression

  defp e(expression), do: to_string(expression)

  describe "expr/1" do
    test "quotes columns" do
      assert e(expr(added)) == ~S|"added"|
      assert e(expr(__time)) == ~S|"__time"|
      assert e(expr(:isRobot)) == ~S|"isRobot"|
    end

    test "writes literals" do
      assert e(expr("it's")) == ~S|'it\'s'|
      assert e(expr(~S"a\b")) == ~S|'a\\b'|
      assert e(expr(1)) == "1"
      assert e(expr(1.5)) == "1.5"
      assert e(expr(nil)) == "null"
      assert e(expr(true)) == "1"
      assert e(expr(false)) == "0"
      assert e(expr([1, 2])) == "[1, 2]"
      assert e(expr(-1)) == "-1"
      assert e(expr(__time > ~U[2016-06-27 00:00:00Z])) == ~S|("__time" > 1466985600000)|
    end

    test "writes operators with explicit precedence" do
      assert e(expr(a + b * c)) == ~S|("a" + ("b" * "c"))|
      assert e(expr((a + b) * c)) == ~S|(("a" + "b") * "c")|
      assert e(expr(a ** 2)) == ~S|("a" ^ 2)|
      assert e(expr(rem(a, 2))) == ~S|("a" % 2)|
      assert e(expr(a >= 1 and b != 2)) == ~S|(("a" >= 1) && ("b" != 2))|
      assert e(expr(a < 1 or b <= 2)) == ~S{(("a" < 1) || ("b" <= 2))}
      assert e(expr(a > 1 && not b)) == ~S|(("a" > 1) && !"b")|
      assert e(expr(!a || -b == 1)) == ~S{(!"a" || (-"b" == 1))}
    end

    test "writes function calls" do
      assert e(expr(nvl(user, "anonymous"))) == ~S|nvl("user", 'anonymous')|
      assert e(expr(timestamp_floor(__time, "PT1H"))) == ~S|timestamp_floor("__time", 'PT1H')|
      assert e(expr(array(a, b))) == ~S|array("a", "b")|
      assert e(expr(now())) == "now()"
    end

    test "writes piped function calls" do
      assert e(expr(user |> nvl("anonymous") |> upper())) == ~S|upper(nvl("user", 'anonymous'))|
      assert e(expr(user |> nvl("a") == "b")) == ~S|(nvl("user", 'a') == 'b')|
    end

    test "writes if in either form" do
      assert e(expr(if(a > 0, a, 0))) == ~S|if(("a" > 0), "a", 0)|
      assert e(expr(if a > 0, do: a, else: 0)) == ~S|if(("a" > 0), "a", 0)|
    end

    test "interpolates pinned values as literals" do
      value = "x' || 1 == 1 || '"
      assert e(expr(page == ^value)) == ~S{("page" == 'x\' || 1 == 1 || \'')}
      assert e(expr(added > ^10)) == ~S|("added" > 10)|
      assert e(expr(^[1, 2])) == "[1, 2]"
      assert e(expr(__time > ^~U[2016-06-27 00:00:00Z])) == ~S|("__time" > 1466985600000)|
    end

    test "interpolates pinned expressions as subexpressions" do
      rate = expr(added / delta)
      assert e(expr(^rate * 100)) == ~S|(("added" / "delta") * 100)|
      assert e(expr(^column(~S|we"ird|) + 1)) == ~S|("we\"ird" + 1)|
    end

    test "rejects syntax with no Druid equivalent" do
      assert_raise ArgumentError, ~r/<> isn't supported/, fn ->
        Code.eval_quoted(quote(do: expr(a <> "b")), [], __ENV__)
      end

      assert_raise ArgumentError, ~r/must hold only literals/, fn ->
        Code.eval_quoted(quote(do: expr([a, 1])), [], __ENV__)
      end

      assert_raise ArgumentError, ~r/can't write/, fn ->
        Code.eval_quoted(quote(do: expr(String.length(a))), [], __ENV__)
      end
    end
  end

  test "encodes to JSON as the expression string" do
    assert Jason.encode!(%{expression: expr(a + 1)}) == ~S|{"expression":"(\"a\" + 1)"}|
  end

  test "inspects as the expression" do
    assert inspect(expr(a + 1)) == ~S|#Ecto.Druid.Native.Expression<("a" + 1)>|
  end

  test "literal/1 rejects values with no literal form" do
    assert_raise ArgumentError, fn -> Expression.literal(%{a: 1}) end
  end
end
