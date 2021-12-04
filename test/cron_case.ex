defmodule CronCase do
  @moduledoc """
  A CaseTemplate providing generators and assertions for property tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnitProperties, async: true

      @spec datetime(DateTime.t(), DateTime.t()) :: StreamData.t(DateTime.t())
      def datetime(%DateTime{} = from, %DateTime{} = to) do
        from = DateTime.to_unix(from)
        to = DateTime.to_unix(to)

        from..to
        |> integer()
        |> map(fn unix -> DateTime.from_unix!(unix) end)
      end

      @spec cron(atom()) :: StreamData.t(String.t())
      def cron(mode) do
        mode
        |> cron_tuple()
        |> cron_string()
      end

      @spec assert_order([NaiveDateTime.t()]) :: true | no_return()
      def assert_order(list) do
        list
        |> Enum.zip(Enum.drop(list, 1))
        |> Enum.each(fn {datetime1, datetime2} ->
          assert NaiveDateTime.compare(datetime1, datetime2) == :lt
        end)

        true
      end

      @spec assert_match(Cron.t(), NaiveDateTime.t()) :: true | no_return()
      def assert_match(%Cron{} = cron, %NaiveDateTime{} = datetime) do
        assert_field(:second, datetime, cron)
        assert_field(:minute, datetime, cron)
        assert_field(:hour, datetime, cron)
        assert_field(:day, datetime, cron)
        assert_field(:month, datetime, cron)
      end

      defp assert_field(:day, datetime, %Cron{day_of_week: day_of_week} = cron)
           when day_of_week != 0..6 do
        day = match?(cron, :day, datetime.day)
        day_of_week = match?(cron, :day_of_week, Date.day_of_week(datetime, :sunday) - 1)

        assert day or day_of_week,
               """
               invalid value for :day - \
               datetime: #{inspect(datetime)}, \
               cron: #{inspect(cron)}, \
               day: #{day}, \
               day_of_week: #{day_of_week}
               """
      end

      defp assert_field(field, datetime, cron) do
        value = Map.fetch!(datetime, field)

        assert match?(cron, field, value),
               """
               invalid value for #{inspect(field)} - \
               datetime: #{inspect(datetime)} \
               cron: #{inspect(cron)}
               """
      end

      defp match?(cron, field, value) do
        case Map.fetch!(cron, field) do
          %Range{} = range -> value in range
          [_ | _] = list -> Enum.member?(list, value)
          int -> int == value
        end
      end

      defp cron_tuple(mode) do
        tuple({
          cron_field(mode, "0", 0..59),
          cron_field(mode, "*", 0..59),
          cron_field(mode, "*", 0..23),
          cron_field(mode, "*", 1..31),
          cron_field(mode, "*", 1..12),
          cron_field(mode, "*", 0..6)
        })
      end

      defp cron_string(%StreamData{} = stream) do
        stream
        |> map(&Tuple.to_list/1)
        |> map(fn list -> Enum.join(list, " ") end)
      end

      defp cron_field(:simple, default, range) do
        one_of([
          constant(default),
          integer(range)
        ])
      end

      defp cron_field(:step, default, range) do
        one_of([
          constant(default),
          integer(range),
          step(range)
        ])
      end

      defp cron_field(:multi, default, range) do
        one_of([
          constant(default),
          integer(range),
          step(range),
          multi(default, range)
        ])
      end

      defp cron_field(:multi, range) do
        one_of([
          integer(range),
          step(range)
        ])
      end

      defp step(%Range{first: from, last: last}) do
        to = div(last, 3)

        {integer(from..to), integer((from + 2)..to)}
        |> tuple()
        |> map(fn {from, step} -> "#{from}/#{step}" end)
      end

      defp multi(default, range) do
        :multi
        |> cron_field(range)
        |> list_of(length: 2..5)
        |> map(fn list -> Enum.join(list, ",") end)
      end
    end
  end
end
