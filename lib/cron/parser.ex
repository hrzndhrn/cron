defmodule Cron.Parser do
  @moduledoc false

  @ranges second: 0..59,
          minute: 0..59,
          hour: 0..23,
          day: 1..31,
          month: 1..12,
          day_of_week: 0..6

  @days_of_week %{
    "SUN" => 0,
    "MON" => 1,
    "TUE" => 2,
    "WED" => 3,
    "THU" => 4,
    "FRI" => 5,
    "SAT" => 6
  }

  @months %{
    "JAN" => 1,
    "FEB" => 2,
    "MAR" => 3,
    "APR" => 4,
    "MAY" => 5,
    "JUN" => 6,
    "JUL" => 7,
    "AUG" => 8,
    "SEP" => 9,
    "OCT" => 10,
    "NOV" => 11,
    "DEC" => 12
  }

  @spec run(String.t()) :: {:ok, keyword()} | :error | {:error, atom()}
  def run(string) do
    with {:ok, split} <- split(string),
         {:ok, data} <- parse(split) do
      validate(data)
    end
  end

  defp split(string) do
    case string |> String.trim() |> String.split(" ") do
      [_minute, _hour, _day, _month, _day_of_week] = list -> {:ok, list}
      [_second, _minute, _hour, _day, _month, _day_of_week] = list -> {:ok, list}
      _list -> :error
    end
  end

  defp validate(data) do
    case data |> Keyword.take([:day, :month]) |> valid?() do
      true -> {:ok, data}
      false -> {:error, :unreachable}
    end
  end

  defp parse([minute, hour, day, month, day_of_week]) do
    parse(["0", minute, hour, day, month, day_of_week])
  end

  defp parse([second, minute, hour, day, month, day_of_week]) do
    with {:ok, second} <- parse(second, :second),
         {:ok, minute} <- parse(minute, :minute),
         {:ok, hour} <- parse(hour, :hour),
         {:ok, day} <- parse(day, :day),
         {:ok, month} <- parse(month, :month),
         {:ok, day_of_week} <- parse(day_of_week, :day_of_week) do
      {:ok,
       [
         second: second,
         minute: minute,
         hour: hour,
         day: day,
         month: month,
         day_of_week: day_of_week
       ]}
    end
  end

  defp parse("*", field), do: Keyword.fetch(@ranges, field)

  defp parse(string, field), do: parse(string, field, @ranges[field])

  defp parse("*", field, _range), do: Keyword.fetch(@ranges, field)

  defp parse(string, field, range) do
    cond do
      int?(string) ->
        parse_int(string, field, range)

      multi?(string) ->
        parse_multi(string, field)

      step?(string) ->
        parse_step(string, field, range)

      range?(string) ->
        parse_range(string, field, range)

      field == :day_of_week ->
        parse_day_of_week(string)

      field == :month ->
        parse_month(string)

      true ->
        {:error, [{field, string}]}
    end
  end

  defp int?(string), do: String.match?(string, ~r/^[0-9]+$/)

  defp multi?(string), do: String.match?(string, ~r/^.+,.+$/)

  defp range?(string), do: String.match?(string, ~r/^.+-.+$/)

  defp step?(string), do: String.match?(string, ~r/^.+\/.+$/)

  defp parse_int(string, field, range) do
    value = String.to_integer(string)

    case value in range do
      true -> {:ok, value}
      false -> {:error, [{field, string}]}
    end
  end

  defp parse_step(string, field, range) do
    string
    |> String.split("/", parts: 2)
    |> Enum.map(fn sub -> parse(sub, field, range) end)
    |> step(range, string, field)
  end

  defp step([{:ok, %{first: from, last: to}}, {:ok, step}], _range, _string, _field)
       when is_integer(step) and step > 0 do
    {:ok, Enum.take_every(from..to, step)}
  end

  defp step([{:ok, from}, {:ok, step}], %{last: to}, _string, _field)
       when is_integer(step) and step > 0 do
    {:ok, Enum.take_every(from..to, step)}
  end

  defp step(_list, _range, string, field), do: {:error, [{field, string}]}

  defp parse_range(string, field, range) do
    string
    |> String.split("-", parts: 2)
    |> Enum.map(fn sub -> parse(sub, field, range) end)
    |> range(string, field)
  end

  defp range([{:ok, from}, {:ok, to}], _string, _field) when from < to, do: {:ok, from..to}

  defp range(_list, string, field), do: {:error, [{field, string}]}

  defp parse_day_of_week(string) do
    with :error <- Map.fetch(@days_of_week, String.upcase(string)) do
      {:error, [day_of_week: string]}
    end
  end

  defp parse_month(string) do
    with :error <- Map.fetch(@months, String.upcase(string)) do
      {:error, [month: string]}
    end
  end

  defp parse_multi(string, field) do
    with [_head | _tail] = list <- do_parse_multi(string, field) do
      {:ok, expand(list)}
    end
  end

  defp do_parse_multi(string, field) do
    string
    |> String.split(",")
    |> Enum.reduce_while([], fn sub, acc ->
      case parse(sub, field) do
        {:ok, value} -> {:cont, [value | acc]}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp expand(list) do
    list
    |> Enum.flat_map(fn
      %Range{} = range -> Enum.into(range, [])
      list when is_list(list) -> list
      value -> [value]
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> unify()
  end

  defp unify([value]), do: value

  defp unify(list) do
    case to_range(list) do
      {:ok, range} -> range
      :error -> list
    end
  end

  defp to_range([head, next | rest]) when head == next - 1 do
    to_range(rest, head..next)
  end

  defp to_range(_list), do: :error

  defp to_range([], range), do: {:ok, range}

  defp to_range([head | rest], %{last: last} = range) when head == last + 1 do
    to_range(rest, %{range | last: head})
  end

  defp to_range(_list, _range), do: :error

  defp valid?(day: %Range{first: first}, month: _month) when first <= 29, do: true

  defp valid?(day: _day, month: %Range{}), do: true

  defp valid?(day: day, month: 2), do: day <= 29

  defp valid?(day: day, month: month) do
    case max_day(month) do
      30 -> min_day(day) <= 30
      31 -> true
    end
  end

  defp valid?(_day_month), do: false

  defp min_day([min | _rest]), do: min

  defp min_day(%Range{first: first}), do: first

  defp min_day(day), do: day

  defp max_day(month) do
    month
    |> List.wrap()
    |> Enum.reduce(0, fn month, max ->
      month
      |> days_in_month()
      |> max(max)
    end)
  end

  defp days_in_month(month) do
    cond do
      month == 2 -> 29
      month in [4, 6, 9, 11] -> 30
      true -> 31
    end
  end
end
