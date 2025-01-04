defmodule Cron.Calc do
  @moduledoc false

  @second 1
  @minute 60 * @second
  @hour 60 * @minute
  @day 24 * @hour

  @spec next(NaiveDateTime.t(), Cron.t()) :: NaiveDateTime.t()
  def next(%NaiveDateTime{} = datetime, %Cron{} = cron) do
    with ^datetime <- update(datetime, cron, :asc) do
      datetime
      |> NaiveDateTime.add(@second)
      |> update(cron, :asc)
    end
  end

  @spec previous(NaiveDateTime.t(), Cron.t()) :: NaiveDateTime.t()
  def previous(%NaiveDateTime{} = datetime, %Cron{} = cron) do
    with ^datetime <- update(datetime, cron, :desc) do
      datetime
      |> NaiveDateTime.add(-@second)
      |> update(cron, :desc)
    end
  end

  @spec match?(NaiveDateTime.t(), Cron.t()) :: boolean()
  def match?(%NaiveDateTime{} = datetime, %Cron{} = cron) do
    datetime == update(datetime, cron, :asc)
  end

  defp update(datetime, cron, order) do
    datetime
    |> update(cron, :month, order)
    |> update(cron, :day, order)
    |> update(cron, :hour, order)
    |> update(cron, :minute, order)
    |> update(cron, :second, order)
  end

  defp update(datetime, %Cron{month: 1..12}, :month, _order), do: datetime

  defp update(datetime, %Cron{hour: 0..23}, :hour, _order), do: datetime

  defp update(datetime, %Cron{minute: 0..59}, :minute, _order), do: datetime

  defp update(datetime, %Cron{second: 0..59}, :second, _order), do: datetime

  defp update(datetime, cron, :day, order) do
    case {cron.day == 1..31, cron.day_of_week == 0..6} do
      {true, true} ->
        datetime

      {false, false} ->
        update(datetime, cron, :union, order)

      _else ->
        new = value(datetime.day, cron, :day, order)
        update(datetime, cron, :day, order, {datetime.day, new})
    end
  end

  defp update(datetime, cron, :union, order) do
    min_max_datetime(
      update(datetime, %{cron | day: 1..31}, order),
      update(datetime, %{cron | day_of_week: 0..6}, order),
      order
    )
  end

  defp update(datetime, cron, field, order) do
    actual = Map.fetch!(datetime, field)
    new = value(actual, cron, field, order)

    update(datetime, cron, field, order, {actual, new})
  end

  defp update(datetime, _cron, :month, :asc, {actual, new}) when actual < new do
    reset(%{datetime | month: new}, :month, :asc)
  end

  defp update(%{year: year} = datetime, _cron, :month, :asc, {actual, new}) when actual > new do
    reset(%{datetime | year: year + 1, month: new}, :month, :asc)
  end

  defp update(%{year: year} = datetime, _cron, :month, :desc, {actual, new}) when actual < new do
    reset(%{datetime | year: year - 1, month: new}, :month, :desc)
  end

  defp update(datetime, _cron, :month, :desc, {actual, new}) when actual > new do
    reset(%{datetime | month: new}, :month, :desc)
  end

  defp update(datetime, cron, :day, :asc, {actual, actual}) do
    case valid_day?(datetime, cron) do
      true ->
        datetime

      false ->
        datetime
        |> next_day(cron)
        |> reset(:day, :asc)
        |> update(cron, :month, :asc)
        |> update(cron, :day, :asc)
    end
  end

  defp update(datetime, cron, :day, :asc, {actual, new}) when actual < new do
    updated = %{datetime | day: new}

    updated =
      case valid_day?(updated, cron) do
        true -> updated
        false -> next_day(datetime, cron)
      end

    updated
    |> reset(:day, :asc)
    |> update(cron, :month, :asc)
    |> update(cron, :day, :asc)
  end

  defp update(datetime, cron, :day, :asc, {actual, new}) when actual > new do
    datetime
    |> next_month()
    |> reset(:month, :asc)
    |> update(cron, :month, :asc)
    |> update(cron, :day, :asc)
  end

  defp update(datetime, cron, :day, :desc, {actual, actual}) do
    case valid_day?(datetime, cron) do
      true ->
        datetime

      false ->
        datetime
        |> previous_day(cron)
        |> reset(:day, :desc)
        |> update(cron, :month, :desc)
        |> update(cron, :day, :desc)
    end
  end

  defp update(datetime, cron, :day, :desc, {actual, new}) when actual < new do
    datetime
    |> previous_month()
    |> reset(:month, :desc)
    |> update(cron, :month, :desc)
    |> update(cron, :day, :desc)
  end

  defp update(datetime, cron, :day, :desc, {actual, new}) when actual > new do
    %{datetime | day: new}
    |> reset(:day, :desc)
    |> update(cron, :month, :desc)
    |> update(cron, :day, :desc)
  end

  defp update(datetime, _cron, _field, _order, {actual, actual}), do: datetime

  defp update(datetime, _cron, field, :asc, {actual, new}) when actual < new do
    datetime
    |> Map.put(field, new)
    |> reset(field, :asc)
  end

  defp update(datetime, cron, field, :asc, {actual, new}) when actual > new do
    distance = distance(actual, new, field, :asc)

    datetime
    |> NaiveDateTime.add(distance)
    |> reset(field, :asc)
    |> update(cron, :asc)
  end

  defp update(datetime, _cron, field, :desc, {actual, new}) when actual > new do
    datetime
    |> Map.put(field, new)
    |> reset(field, :desc)
  end

  defp update(datetime, cron, field, :desc, {actual, new}) when actual < new do
    distance = distance(actual, new, field, :desc)

    datetime
    |> NaiveDateTime.add(distance)
    |> reset(field, :desc)
    |> update(cron, :desc)
  end

  defp previous_day(datetime, %{day_of_week: day_of_week}) do
    datetime = NaiveDateTime.add(datetime, -@day)
    actual = day_of_week(datetime)
    value = value(actual, day_of_week, :desc)
    distance = distance(actual, value, :day_of_week, :desc)

    NaiveDateTime.add(datetime, distance)
  end

  defp next_day(datetime, %{day_of_week: 0..6}) do
    NaiveDateTime.add(datetime, @day)
  end

  defp next_day(datetime, %{day_of_week: day_of_week}) do
    datetime = NaiveDateTime.add(datetime, @day)
    actual = day_of_week(datetime)
    value = value(actual, day_of_week, :asc)
    distance = distance(actual, value, :day_of_week, :asc)

    NaiveDateTime.add(datetime, distance)
  end

  defp previous_month(%{year: year, month: 1} = datetime) do
    %{datetime | year: year - 1, month: 12}
  end

  defp previous_month(%{month: month} = datetime) do
    %{datetime | month: month - 1}
  end

  defp next_month(%{year: year, month: 12} = datetime) do
    %{datetime | year: year + 1, month: 1}
  end

  defp next_month(%{month: month} = datetime) do
    %{datetime | month: month + 1}
  end

  defp valid_day?(datetime, %Cron{day: 1..31} = cron) do
    with true <- valid_day?(datetime) do
      case Map.fetch!(cron, :day_of_week) do
        day when is_integer(day) -> day_of_week(datetime) == day
        days -> day_of_week(datetime) in days
      end
    end
  end

  defp valid_day?(datetime, _cron) do
    valid_day?(datetime)
  end

  defp valid_day?(%{day: day} = datetime) do
    day <= Date.days_in_month(datetime)
  end

  defp day_of_week(datetime) do
    Date.day_of_week(datetime, :sunday) - 1
  end

  defp value(actual, cron, field, order) do
    value(actual, Map.fetch!(cron, field), order)
  end

  defp value(_actual, value, _order) when is_integer(value), do: value

  defp value(actual, %Range{} = range, order) do
    cond do
      actual in range -> actual
      order == :asc -> range.first
      order == :desc -> range.last
    end
  end

  defp value(actual, [first | _rest] = list, :asc) do
    Enum.find(list, first, fn value -> value >= actual end)
  end

  defp value(actual, [_head | _tail] = list, :desc) do
    [first | _rest] = list = Enum.reverse(list)
    Enum.find(list, first, fn value -> value <= actual end)
  end

  defp distance(actual, new, :second, :asc) when actual > new do
    60 - actual + new
  end

  defp distance(actual, new, :second, :desc) when actual < new do
    (60 - new + actual) * -@second
  end

  defp distance(actual, new, :minute, :asc) when actual > new do
    (60 - actual + new) * @minute
  end

  defp distance(actual, new, :minute, :desc) when actual < new do
    (60 - new + actual) * -@minute
  end

  defp distance(actual, new, :hour, :asc) when actual > new do
    (24 - actual + new) * @hour
  end

  defp distance(actual, new, :hour, :desc) when actual < new do
    (24 - new + actual) * -@hour
  end

  defp distance(actual, new, :day_of_week, :asc) do
    cond do
      actual == new -> 0
      actual < new -> (new - actual) * @day
      actual > new -> (6 - actual + new) * @day
    end
  end

  defp distance(actual, new, :day_of_week, :desc) do
    cond do
      actual == new -> 0
      actual > new -> (actual - new) * -@day
      actual < new -> (6 - new + actual) * -@day
    end
  end

  defp reset(datetime, :second, _order), do: datetime

  defp reset(datetime, field, :asc) do
    case field do
      :month ->
        %{datetime | day: 1, hour: 0, minute: 0, second: 0}

      :day ->
        %{datetime | hour: 0, minute: 0, second: 0}

      :hour ->
        %{datetime | minute: 0, second: 0}

      :minute ->
        %{datetime | second: 0}
    end
  end

  defp reset(datetime, field, :desc) do
    case field do
      :month ->
        %{datetime | day: Date.days_in_month(datetime), hour: 23, minute: 59, second: 59}

      :day ->
        %{datetime | hour: 23, minute: 59, second: 59}

      :hour ->
        %{datetime | minute: 59, second: 59}

      :minute ->
        %{datetime | second: 59}
    end
  end

  defp min_max_datetime(datetime1, datetime2, :asc) do
    case NaiveDateTime.compare(datetime1, datetime2) do
      :gt -> datetime2
      _else -> datetime1
    end
  end

  defp min_max_datetime(datetime1, datetime2, :desc) do
    case NaiveDateTime.compare(datetime1, datetime2) do
      :lt -> datetime2
      _else -> datetime1
    end
  end
end
