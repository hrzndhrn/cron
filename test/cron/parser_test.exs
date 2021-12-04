defmodule Cron.ParserTest do
  use ExUnit.Case, async: true

  import Prove
  alias Cron.Parser

  prove Parser.run("* * * * *") == cron()
  prove Parser.run("* * * * * *") == cron(second: 0..59)
  prove Parser.run(" * * * * * *") == cron(second: 0..59)
  prove Parser.run("* * * * * * ") == cron(second: 0..59)

  prove Parser.run("invalid") == :error
  prove Parser.run("*      * * * *") == :error

  batch "second" do
    prove Parser.run("5 * * * * *") == cron(second: 5)
    prove Parser.run("5,7,9 * * * * *") == cron(second: [5, 7, 9])
    prove Parser.run("5-9 * * * * *") == cron(second: 5..9)
    prove Parser.run("5-9,11 * * * * *") == cron(second: [5, 6, 7, 8, 9, 11])
    prove Parser.run("53/2 * * * * *") == cron(second: [53, 55, 57, 59])
    prove Parser.run("10-20/2 * * * * *") == cron(second: [10, 12, 14, 16, 18, 20])

    prove Parser.run("60 * * * * *") == {:error, second: "60"}
    prove Parser.run("5,77,9 * * * * *") == {:error, second: "77"}
    prove Parser.run("5-99 * * * * *") == {:error, second: "5-99"}
    prove Parser.run("MON * * * * *") == {:error, second: "MON"}
    prove Parser.run("10-70/2 * * * * *") == {:error, second: "10-70/2"}
    prove Parser.run("10/2-5 * * * * *") == {:error, second: "10/2-5"}
    prove Parser.run("*/0 * * * * *") == {:error, second: "*/0"}
  end

  batch "minute" do
    prove Parser.run("* 5 * * * *") == cron(minute: 5, second: 0..59)
    prove Parser.run("5 * * * *") == cron(minute: 5)
    prove Parser.run("10/5 * * * *") == cron(minute: [10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
    prove Parser.run("*/15 * * * *") == cron(minute: [0, 15, 30, 45])
    prove Parser.run("5,7,9 * * * *") == cron(minute: [5, 7, 9])
    prove Parser.run("5-9 * * * *") == cron(minute: 5..9)
    prove Parser.run("5-9,11 * * * *") == cron(minute: [5, 6, 7, 8, 9, 11])
    prove Parser.run("15,30,45,*/15 * * * *") == cron(minute: [0, 15, 30, 45])

    prove Parser.run("0 15-18,20/12,1-15/5 * * * *") ==
            cron(minute: [1, 6, 11, 15, 16, 17, 18, 20, 32, 44, 56])

    prove Parser.run("60 * * * *") == {:error, minute: "60"}
    prove Parser.run("5,77,9 * * * *") == {:error, minute: "77"}
    prove Parser.run("5-99 * * * *") == {:error, minute: "5-99"}
    prove Parser.run("MON * * * *") == {:error, minute: "MON"}
  end

  batch "day" do
    prove Parser.run("0 * * 30-31 11 *") == cron(day: 30..31, month: 11)
  end

  batch "day_of_week" do
    prove Parser.run("* * * * MON") == cron(day_of_week: 1)
    prove Parser.run("* * * * tue") == cron(day_of_week: 2)
    prove Parser.run("* * * * MON-WED") == cron(day_of_week: 1..3)
    prove Parser.run("* * * * 5") == cron(day_of_week: 5)

    prove Parser.run("* * * MON-WED *") == {:error, month: "MON-WED"}
    prove Parser.run("* * * * FOO") == {:error, day_of_week: "FOO"}
  end

  batch "month" do
    prove Parser.run("* * * jan *") == cron(month: 1)
    prove Parser.run("* * * FEB *") == cron(month: 2)
    prove Parser.run("* * * MAR-JUN *") == cron(month: 3..6)
    prove Parser.run("* * * */3 *") == cron(month: [1, 4, 7, 10])

    prove Parser.run("* * * 0 *") == {:error, month: "0"}
    prove Parser.run("* * * 13 *") == {:error, month: "13"}
    prove Parser.run("* * * foo *") == {:error, month: "foo"}
  end

  batch "unify" do
    prove Parser.run("1,3 * * * * *") == cron(second: [1, 3])
    prove Parser.run("5,5 * * * * *") == cron(second: 5)
    prove Parser.run("5,6,7 * * * * *") == cron(second: 5..7)
    prove Parser.run("6,7,5 * * * * *") == cron(second: 5..7)
    prove Parser.run("5,8,6 * * * * *") == cron(second: [5, 6, 8])
    prove Parser.run("*/2,1/2 * * * * *") == cron(second: 0..59)
  end

  batch "validate" do
    prove Parser.run("* * * 31 2 *") == {:error, :unreachable}
    prove Parser.run("* * * 30 2 *") == {:error, :unreachable}
    prove Parser.run("* * * 31 4,6 *") == {:error, :unreachable}
    prove Parser.run("* * * 31 9/2 *") == {:error, :unreachable}
    prove Parser.run("* * * 31 11 *") == {:error, :unreachable}
  end

  defp cron(values \\ []) do
    {:ok,
     [
       second: Keyword.get(values, :second, 0),
       minute: Keyword.get(values, :minute, 0..59),
       hour: Keyword.get(values, :hour, 0..23),
       day: Keyword.get(values, :day, 1..31),
       month: Keyword.get(values, :month, 1..12),
       day_of_week: Keyword.get(values, :day_of_week, 0..6)
     ]}
  end
end
