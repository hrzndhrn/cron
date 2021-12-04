defmodule CronTest do
  use CronCase

  doctest Cron

  test "to_string/1" do
    assert to_string(%Cron{}) == "0 * * * * *"
  end

  describe "new/1" do
    test "retruns an ok tuple with cron struct for an expression with 5 fields" do
      expression = "5 * * * *"
      assert Cron.new(expression) == {:ok, %Cron{expression: expression, minute: 5, second: 0}}
    end

    test "retruns an ok tuple with cron struct for an expression with 6 fields" do
      expression = "10 5 * * * *"
      assert Cron.new(expression) == {:ok, %Cron{expression: expression, minute: 5, second: 10}}
    end

    test "returns an :error for an invalid expression" do
      assert Cron.new("foo") == :error
    end

    test "returns an :error tuple for an invalid field" do
      assert Cron.new("99 * * * *") == {:error, minute: "99"}
    end
  end

  describe "new!/1" do
    test "returns a cron struct for an expression with 5 fields" do
      expression = "5 * * * *"
      assert Cron.new!(expression) == %Cron{expression: expression, minute: 5, second: 0}
    end

    test "returns a cron struct for an expression with 6 fields" do
      expression = "10 5 * * * *"
      assert Cron.new!(expression) == %Cron{expression: expression, minute: 5, second: 10}
    end

    test "raises an exception for an invalid expression" do
      message = ~s|invalid cron expression: "foo"|

      assert_raise ArgumentError, message, fn ->
        Cron.new!("foo")
      end
    end

    test "raises an exception for an invalid field" do
      message = ~s|invalid cron expression: [month: "99"]|

      assert_raise ArgumentError, message, fn ->
        Cron.new!("* * * 99 *")
      end
    end
  end

  describe "next/2" do
    test "uses NaiveDateTime.utc_now() as default" do
      cron = Cron.new!("10 * * * * *")
      next = Cron.next(cron)
      assert NaiveDateTime.diff(next, NaiveDateTime.utc_now()) <= 60
    end
  end

  describe "previous/2" do
    test "uses NaiveDateTime.utc_now() as default" do
      cron = Cron.new!("10 * * * * *")
      prev = Cron.previous(cron)
      assert NaiveDateTime.diff(NaiveDateTime.utc_now(), prev) <= 60
    end
  end

  describe "next_while!/3" do
    test "returns the next execution datetime" do
      cron = Cron.new!("0 30 12 * * *")

      next =
        Cron.next_while!(
          cron,
          ~N[2022-01-01 00:00:00],
          fn datetime -> Date.day_of_week(datetime) in 1..5 end
        )

      assert next == ~N[2022-01-03 12:30:00]
    end

    test "raises an error if no execution datetime can be found" do
      message = "no follow up datetime found"

      assert_raise RuntimeError, message, fn ->
        "1 1 1 1 1 *"
        |> Cron.new!()
        |> Cron.next_while!(fn _datetime -> false end)
      end
    end
  end

  describe "until_while!/3" do
    test "returns the milliseconds until the next execution datetime" do
      cron = Cron.new!("0 30 12 * * *")

      until =
        Cron.until_while!(
          cron,
          ~N[2022-01-01 00:00:00],
          fn datetime -> Date.day_of_week(datetime) in 1..5 end
        )

      assert until == 217_800_000
    end

    test "raises an error if no execution datetime can be found" do
      message = "no follow up datetime found"

      assert_raise RuntimeError, message, fn ->
        "1 1 1 1 1 *"
        |> Cron.new!()
        |> Cron.until_while!(fn _datetime -> false end)
      end
    end
  end

  describe "previous_while!/3" do
    test "returns the previous execution datetime" do
      cron = Cron.new!("0 30 12 * * *")

      previous =
        Cron.previous_while!(
          cron,
          ~N[2022-01-02 00:00:00],
          fn datetime -> Date.day_of_week(datetime) in 1..5 end
        )

      assert previous == ~N[2021-12-31 12:30:00]
    end

    test "raises an error if no execution datetime can be found" do
      message = "no previous datetime found"

      assert_raise RuntimeError, message, fn ->
        "1 1 1 1 1 *"
        |> Cron.new!()
        |> Cron.previous_while!(fn _datetime -> false end)
      end
    end
  end

  describe "since_while!/3" do
    test "returns the milliseconds since the previous execution datetime" do
      cron = Cron.new!("0 30 12 * * *")

      previous =
        Cron.since_while!(
          cron,
          ~N[2022-01-02 00:00:00],
          fn datetime -> Date.day_of_week(datetime) in 1..5 end
        )

      assert previous == 127_800_000
    end

    test "raises an error if no execution datetime can be found" do
      message = "no previous datetime found"

      assert_raise RuntimeError, message, fn ->
        "1 1 1 1 1 *"
        |> Cron.new!()
        |> Cron.since_while!(fn _datetime -> false end)
      end
    end
  end

  describe "stream/2" do
    test "returns a stream with default order :asc and default :from" do
      stream =
        "30 40 12 10 * *"
        |> Cron.new!()
        |> Cron.stream()

      assert_order([NaiveDateTime.utc_now() | Enum.take(stream, 3)])
    end

    test "returns a stream with default order :asc" do
      stream =
        "30 40 12 10 * *"
        |> Cron.new!()
        |> Cron.stream(from: ~U[2022-06-05 00:00:00Z])

      assert Enum.take(stream, 3) == [
               ~N[2022-06-10 12:40:30],
               ~N[2022-07-10 12:40:30],
               ~N[2022-08-10 12:40:30]
             ]
    end

    test "raises an ArgumentError exception for an invalid :from" do
      message = ~s|invalid value for :from, got "foo"|

      assert_raise ArgumentError, message, fn ->
        Cron.stream(%Cron{}, from: "foo")
      end
    end

    test "raises an ArgumentError exception for an invalid :order" do
      message = ~s|invalid value for :order, got "foo"|

      assert_raise ArgumentError, message, fn ->
        Cron.stream(%Cron{}, order: "foo")
      end
    end
  end

  @tag timeout: 600_000
  property "simple cron expressions" do
    check all cron <- cron(:simple),
              datetime <- datetime(~U[2000-01-01 00:00:00Z], ~U[2001-01-01 00:00:00Z]) do
      property_check(cron, datetime)
    end
  end

  @tag timeout: 600_000
  property "cron expressions with steps" do
    check all cron <- cron(:step),
              datetime <- datetime(~U[2000-01-01 00:00:00Z], ~U[2001-01-01 00:00:00Z]) do
      property_check(cron, datetime)
    end
  end

  @tag timeout: 600_000
  property "cron expressions with steps and multis" do
    check all cron <- cron(:multi),
              datetime <- datetime(~U[2000-01-01 00:00:00Z], ~U[2001-01-01 00:00:00Z]) do
      property_check(cron, datetime)
    end
  end

  defp property_check(cron, datetime) when is_binary(cron) do
    case Cron.new(cron) do
      {:ok, cron} ->
        property_check(cron, datetime)

      {:error, reason} ->
        assert reason == :unreachable
    end
  end

  defp property_check(cron, datetime) do
    next = cron |> Cron.stream(from: datetime, order: :asc) |> Enum.take(2)
    prev = cron |> Cron.stream(from: datetime, order: :desc) |> Enum.take(2)

    prev
    |> Enum.reverse()
    |> Enum.concat([datetime | next])
    |> assert_order()

    prev
    |> Enum.concat(next)
    |> Enum.each(fn result ->
      assert_match(cron, result)
    end)
  end
end
