defmodule Cron do
  @moduledoc """
  `Cron` parses cron expressions and calculates execution timings.

  Expressions with 6 and 5 fields are expected. The variant with 6 fields adds a
  field for seconds at the first position. The variant with 5 fields corresponds
  to the standard Unix behavior. The field `second` will be set to `0` when
  `Cron.new/1` gets 5 fields.

  Possible values for the fields:
  ```
  +----------- second (0 - 59)
  | +--------- minute (0 - 59)
  | | +------- hour (0 - 23)
  | | | +----- day of the month (1 - 31)
  | | | | +--- month (1 - 12)
  | | | | | +- day of the week (0 - 6, SUN - SAT)
  | | | | | |
  * * * * * *
  ```

  A field may contain an asterisk `*`, which means any of the possible values.

  A range of values can be specified with an `-`.
  Example: `10-15`.

  A `/` can be used to setup steps. The value before the `/` specifies the start
  value and the value behind the `/` specifies the step width.
  Example: `*/2`, `4/2`.

  Multiple values can be declared with a `,` separated list without any
  whitespace.
  Example: `1,5,10-15,*/2`.

  The fields `month` and `day_of_week` are also accept names. Month accepts
  `Jan`, `Feb`, `Mar`, `Apr`, `May`, `Jun`, `Jul`, `Aug`, `Sep`. `Oct`, `Nov`
  and `Dez`. The case does not matter.

  `day_of_week` accepts `Sun`, `Mon`, `Tue`, `Wed`, `Thu`, `Fri` and `Sat`. The
  case does not matter. Keep in mind that `Sun` is equal to `0` and `Sat` is
  equal to `6`.

  All `Cron` functions are working with `NaiveDateTime` or `DateTime` that are
  using the `Calendar.ISO`. Any `DateTime` must have the time zone `Etc/UTC`.

  ## Examples

  A cron expression that triggers daily at 12:00:00

      iex> "0 12 * * *"
      ...> |> Cron.new!()
      ...> |> Cron.next(~U[2021-12-06 22:11:44Z])
      ~U[2021-12-07 12:00:00Z]

  `Cron.stream/2` calculates multiple values. The following cron expression
  triggers ever 30 minutes from 12 to 14 at the first day in a month.

      iex> "0 */30 12-14 1 * *"
      ...> |> Cron.new!()
      ...> |> Cron.stream(from: ~U[2021-12-06 11:22:33Z])
      ...> |> Enum.take(8)
      [
        ~N[2022-01-01 12:00:00],
        ~N[2022-01-01 12:30:00],
        ~N[2022-01-01 13:00:00],
        ~N[2022-01-01 13:30:00],
        ~N[2022-01-01 14:00:00],
        ~N[2022-01-01 14:30:00],
        ~N[2022-02-01 12:00:00],
        ~N[2022-02-01 12:30:00]
      ]
  """

  import Kernel, except: [match?: 2]

  alias Cron.Calc
  alias Cron.Parser

  defstruct expression: "0 * * * * *",
            second: 0,
            minute: 0..59,
            hour: 0..23,
            day: 1..31,
            month: 1..12,
            day_of_week: 0..6

  @type t :: %Cron{
          expression: String.t(),
          second: 0..59 | [0..59, ...] | Range.t(0..59, 0..59),
          minute: 0..59 | [0..59, ...] | Range.t(0..59, 0..59),
          hour: 0..23 | [0..23, ...] | Range.t(0..23, 0..23),
          day: 1..31 | [1..31, ...] | Range.t(1..31, 1..31),
          month: 1..12 | [1..13, ...] | Range.t(1..12, 1..12),
          day_of_week: 0..6 | [0..6, ...] | Range.t(0..6, 0..6)
        }

  @type expression :: String.t()
  @type reason :: atom() | [{atom(), String.t()}]
  @type millisecond :: pos_integer()

  @doc """
  Returns an `:ok` tuple with a cron struct for the given expression string. If
  the expression is invalid an `:error` will be returned.

  Will accept expression with 6 (including `second`) and 5 (`second: 0`) fields.

  ## Examples
      iex> {:ok, cron} = Cron.new("1 2 3 * *")
      iex> cron
      #Cron<1 2 3 * *>

      iex> {:ok, cron} = Cron.new("0 1 2 3 * *")
      iex> cron
      #Cron<0 1 2 3 * *>

      iex> Cron.new("66 1 2 3 * *")
      {:error, second: "66"}
  """
  @spec new(expression()) :: {:ok, Cron.t()} | :error | {:error, reason}
  def new(string) do
    with {:ok, data} <- Parser.run(string) do
      {:ok, struct!(Cron, Keyword.put(data, :expression, string))}
    end
  end

  @doc """
  Same as `new/1`, but raises an `ArgumentError` exception in case of an invalid
  expression.
  """
  @spec new!(expression()) :: Cron.t()
  def new!(string) do
    case new(string) do
      {:ok, cron} ->
        cron

      :error ->
        raise ArgumentError, "invalid cron expression: #{inspect(string)}"

      {:error, reason} ->
        raise ArgumentError, "invalid cron expression: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the next execution datetime.

  If the given `datetime` matches `cron`, then also the following datetime is
  returning. That means the resulting datetime is always greater than the given.
  The function truncates the precision of the given `datetime` to seconds.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 0 * * *")
      iex> Cron.next(cron, ~U[2022-01-01 12:00:00Z])
      ~U[2022-01-02 00:00:00Z]
      iex> Cron.next(cron, ~U[2022-01-02 00:00:00Z])
      ~U[2022-01-03 00:00:00Z]
      iex> Cron.next(cron, ~U[2022-01-02 00:00:00.999Z])
      ~U[2022-01-03 00:00:00Z]
  """
  @spec next(Cron.t(), DateTime.t() | NaiveDateTime.t()) :: DateTime.t() | NaiveDateTime.t()
  def next(cron, datetime \\ NaiveDateTime.utc_now())

  def next(
        %Cron{} = cron,
        %DateTime{calendar: Calendar.ISO, time_zone: "Etc/UTC"} = datetime
      ) do
    cron
    |> next(DateTime.to_naive(datetime))
    |> from_naive!()
  end

  def next(%Cron{} = cron, %NaiveDateTime{calendar: Calendar.ISO} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calc.next(cron)
  end

  @doc """
  Returns an `:ok` tuple with the next execution datetime for which fun returns
  a truthy value.

  If no datetime can be found, an `:error` will be returned.

  The function truncates the precision of the given `datetime` to seconds.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 29 2 *")
      iex> Cron.next_while(cron, fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, ~N[2044-02-29 00:00:00]}
      iex> Cron.next_while(
      ...>   cron, ~U[2044-02-29 00:00:00Z], fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, ~U[2072-02-29 00:00:00Z]}

      iex> {:ok, cron} = Cron.new("0 0 1 1 *")
      iex> Cron.next_while(cron, fn _ -> false end)
      :error
  """
  @spec next_while(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime.t() -> as_boolean(term))
        ) :: {:ok, DateTime.t() | NaiveDateTime.t()} | :error
  def next_while(cron, datetime \\ NaiveDateTime.utc_now(), fun)

  def next_while(%Cron{} = cron, %DateTime{} = datetime, fun) when is_function(fun, 1) do
    cron
    |> next_while(DateTime.to_naive(datetime), fun)
    |> from_naive!()
  end

  def next_while(%Cron{} = cron, %NaiveDateTime{} = datetime, fun) when is_function(fun, 1) do
    get_while(cron, datetime, fun, :asc)
  end

  @doc """
  Same as `next_while/3`, but raises a `RuntimeError` exception in case no
  execution datetime can be found.
  """
  @spec next_while!(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime.t() -> as_boolean(term))
        ) :: DateTime.t() | NaiveDateTime.t()
  def next_while!(cron, datetime \\ NaiveDateTime.utc_now(), fun) do
    case next_while(cron, datetime, fun) do
      {:ok, next} -> next
      :error -> raise "no follow up datetime found"
    end
  end

  @doc """
  Same as `next/3`, but returns the milliseconds until next execution datetime.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 0 * * *")
      iex> Cron.until(cron, ~U[2022-01-01 12:00:00Z])
      43200000
      iex> Cron.until(cron, ~U[2022-01-02 00:00:00Z])
      86400000
      iex> Cron.until(cron, ~U[2022-01-02 00:00:00.999Z])
      86399001
  """
  @spec until(Cron.t(), DateTime.t() | NaiveDateTime.t()) :: millisecond
  def until(%Cron{} = cron, datetime \\ DateTime.utc_now()) do
    cron
    |> next(datetime)
    |> NaiveDateTime.diff(datetime, :millisecond)
  end

  @doc """
  Same as `next_while/3`, but returns the milliseconds until next execution
  datetime.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 29 2 *")
      iex> Cron.until_while(
      ...>   cron,
      ...>   ~U[2022-01-01 00:00:00Z],
      ...>   fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, 699_321_600_000}
      iex> Cron.until_while(
      ...>   cron,
      ...>   ~U[2044-02-28 23:59:59.100Z],
      ...>   fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, 900}

      iex> {:ok, cron} = Cron.new("0 0 1 1 *")
      iex> Cron.until_while(cron, fn _ -> false end)
      :error
  """
  @spec until_while(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime -> as_boolean(term))
        ) :: {:ok, millisecond} | :error
  def until_while(%Cron{} = cron, datetime \\ DateTime.utc_now(), fun) when is_function(fun, 1) do
    with {:ok, next} <- next_while(cron, datetime, fun) do
      {:ok, NaiveDateTime.diff(next, datetime, :millisecond)}
    end
  end

  @doc """
  Same as `until_while!/3`, but raises a `RuntimeError` exception in case no
  execution datetime can be found.
  """
  @spec until_while!(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime -> as_boolean(term))
        ) :: millisecond
  def until_while!(%Cron{} = cron, datetime \\ DateTime.utc_now(), fun)
      when is_function(fun, 1) do
    case until_while(cron, datetime, fun) do
      {:ok, until} -> until
      :error -> raise "no follow up datetime found"
    end
  end

  @doc """
  Returns the previous execution datetime.

  If the given `datetime` matches `cron`, then also the previous datetime is
  returning. That means the resulting datetime is always lower than the given.
  The function truncates the precision of the given `datetime` to seconds.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 0 * * *")
      iex> Cron.previous(cron, ~U[2022-01-01 12:00:00Z])
      ~U[2022-01-01 00:00:00Z]
      iex> Cron.previous(cron, ~U[2022-01-01 00:00:00Z])
      ~U[2021-12-31 00:00:00Z]
      iex> Cron.previous(cron, ~U[2022-01-01 00:00:00.999Z])
      ~U[2021-12-31 00:00:00Z]
  """
  @spec previous(Cron.t(), DateTime.t() | NaiveDateTime.t()) :: DateTime.t() | NaiveDateTime.t()
  def previous(cron, datetime \\ NaiveDateTime.utc_now())

  def previous(
        %Cron{} = cron,
        %DateTime{calendar: Calendar.ISO, time_zone: "Etc/UTC"} = datetime
      ) do
    cron
    |> previous(DateTime.to_naive(datetime))
    |> from_naive!()
  end

  def previous(%Cron{} = cron, %NaiveDateTime{calendar: Calendar.ISO} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calc.previous(cron)
  end

  @doc """
  Returns an `:ok` tuple with the previous execution datetime for which fun
  returns a truthy value.

  If no datetime can be found, an `:error` will be returned.

  The function truncates the precision of the given `datetime` to seconds.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 29 2 *")
      iex> Cron.previous_while(cron, fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, ~N[2016-02-29 00:00:00]}
      iex> Cron.previous_while(
      ...>   cron, ~U[2016-02-29 00:00:00Z], fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, ~U[1988-02-29 00:00:00Z]}

      iex> {:ok, cron} = Cron.new("0 0 1 1 *")
      iex> Cron.previous_while(cron, fn _ -> false end)
      :error
  """
  @spec previous_while(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime.t() -> as_boolean(term))
        ) :: {:ok, DateTime.t() | NaiveDateTime.t()} | :error
  def previous_while(cron, datetime \\ NaiveDateTime.utc_now(), fun)

  def previous_while(%Cron{} = cron, %DateTime{} = datetime, fun) when is_function(fun, 1) do
    cron
    |> previous_while(DateTime.to_naive(datetime), fun)
    |> from_naive!()
  end

  def previous_while(%Cron{} = cron, %NaiveDateTime{} = datetime, fun) when is_function(fun, 1) do
    get_while(cron, datetime, fun, :desc)
  end

  @doc """
  Same as `previous_while/3`, but raises a `RuntimeError` exception in case no
  execution datetime can be found.
  """
  @spec previous_while!(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime.t() -> as_boolean(term))
        ) :: DateTime.t() | NaiveDateTime.t()
  def previous_while!(cron, datetime \\ NaiveDateTime.utc_now(), fun) when is_function(fun, 1) do
    case previous_while(cron, datetime, fun) do
      {:ok, previous} -> previous
      :error -> raise "no previous datetime found"
    end
  end

  @doc """
  Same as `previous/3`, but returns the milliseconds since last execution
  datetime.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 0 * * *")
      iex> Cron.since(cron, ~U[2022-01-02 00:00:00Z])
      86_400_000
      iex> Cron.since(cron, ~U[2022-01-02 00:01:00Z])
      60_000
      iex> Cron.since(cron, ~U[2022-01-02 00:01:00.999Z])
      60_999
      iex> Cron.since(cron, ~U[2022-01-02 00:00:00.999Z])
      86_400_999
  """
  @spec since(Cron.t(), DateTime.t() | NaiveDateTime.t()) :: millisecond
  def since(%Cron{} = cron, datetime \\ DateTime.utc_now()) do
    NaiveDateTime.diff(datetime, previous(cron, datetime), :millisecond)
  end

  @doc """
  Same as `previous_while/3`, but returns the milliseconds since last execution
  datetime.

  ## Examples

      iex> {:ok, cron} = Cron.new("0 0 29 2 *")
      iex> Cron.since_while(
      ...>   cron,
      ...>   ~U[2022-01-01 00:00:00Z],
      ...>   fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, 184_291_200_000}
      iex> Cron.since_while(
      ...>   cron,
      ...>   ~U[2016-02-29 00:00:01.999Z],
      ...>   fn datetime -> Date.day_of_week(datetime) == 1 end)
      {:ok, 1_999}

      iex> {:ok, cron} = Cron.new("0 0 1 1 *")
      iex> Cron.since_while(cron, fn _ -> false end)
      :error
  """
  @spec since_while(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime -> as_boolean(term))
        ) :: {:ok, millisecond} | :error
  def since_while(%Cron{} = cron, datetime \\ DateTime.utc_now(), fun) do
    with {:ok, previous} <- previous_while(cron, datetime, fun) do
      {:ok, NaiveDateTime.diff(datetime, previous, :millisecond)}
    end
  end

  @doc """
  Same as `since_while!/3`, but raises a `RuntimeError` exception in case no
  execution datetime can be found.
  """
  @spec since_while!(
          Cron.t(),
          DateTime.t() | NaiveDateTime.t(),
          (NaiveDateTime -> as_boolean(term))
        ) :: millisecond
  def since_while!(%Cron{} = cron, datetime \\ DateTime.utc_now(), fun) do
    case since_while(cron, datetime, fun) do
      {:ok, since} -> since
      :error -> raise "no previous datetime found"
    end
  end

  @doc """
  Returns true if the given `datetime` matches the `cron`.

  The function truncates the precision of the given `datetime` to seconds.

  Examples

      iex> cron = Cron.new!("0 * * * *")
      iex> Cron.match?(cron, ~U[2021-11-13 06:41:39Z])
      false
      iex> Cron.match?(cron, ~U[2021-11-13 13:00:00Z])
      true
      iex> Cron.match?(cron, ~U[2021-11-13 13:00:00.999Z])
      true

      iex> "* * * * * *" |> Cron.new!() |> Cron.match?()
      true
  """
  @spec match?(Cron.t(), DateTime.t() | NaiveDateTime.t()) :: boolean()
  def match?(cron, datetime \\ NaiveDateTime.utc_now())

  def match?(
        %Cron{} = cron,
        %DateTime{calendar: Calendar.ISO, time_zone: "Etc/UTC"} = datetime
      ) do
    match?(cron, DateTime.to_naive(datetime))
  end

  def match?(%Cron{} = cron, %NaiveDateTime{calendar: Calendar.ISO} = datetime) do
    datetime
    |> NaiveDateTime.truncate(:second)
    |> Calc.match?(cron)
  end

  @doc """
  Returns a `Stream` for the given `cron`.

  The stream ends after the last execution datetime in the year 9000 or -9000.

  Options:
    * `:from` - the start datetime.
      Defaults to `NaiveDateTime.utc_now("Etc/UTC")`.

    * `:oder` - `:asc` or `:desc` to get execution datetimes before or after
      start datetime. Defaults to `:asc`.

  ## Examples

      iex> cron = Cron.new!("0 0 12 1 * *")
      iex> stream = Cron.stream(cron, from: ~U[2022-06-05 00:00:00Z])
      iex> Enum.take(stream, 3)
      [
        ~N[2022-07-01 12:00:00],
        ~N[2022-08-01 12:00:00],
        ~N[2022-09-01 12:00:00],
      ]
      iex> stream = Cron.stream(cron, from: ~U[2022-06-05 00:00:00Z], order: :desc)
      iex> Enum.take(stream, 3)
      [
        ~N[2022-06-01 12:00:00],
        ~N[2022-05-01 12:00:00],
        ~N[2022-04-01 12:00:00],
      ]
      iex> stream = Cron.stream(cron, from: ~U[9000-10-05 00:00:00Z])
      iex> Enum.take(stream, 3)
      [
        ~N[9000-11-01 12:00:00],
        ~N[9000-12-01 12:00:00]
      ]
  """
  @spec stream(Cron.t(), keyword()) :: Enumerable.t()
  def stream(%Cron{} = cron, opts \\ []) do
    with {:ok, from} <- fetch(opts, :from),
         {:ok, order} <- fetch(opts, :order) do
      Stream.unfold(stream(from, cron, order), fn
        %{year: year} when year > 9000 or year < -9000 -> nil
        acc -> {acc, stream(acc, cron, order)}
      end)
    else
      {:error, [{key, value}]} ->
        raise ArgumentError, "invalid value for #{inspect(key)}, got #{inspect(value)}"
    end
  end

  defp stream(datetime, cron, :asc), do: Calc.next(datetime, cron)

  defp stream(datetime, cron, :desc), do: Calc.previous(datetime, cron)

  defp fetch(opts, :from) do
    case Keyword.fetch(opts, :from) do
      {:ok, %DateTime{} = datetime} ->
        {:ok, datetime |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)}

      {:ok, %NaiveDateTime{} = datetime} ->
        {:ok, NaiveDateTime.truncate(datetime, :second)}

      :error ->
        {:ok, NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)}

      {:ok, invalid} ->
        {:error, from: invalid}
    end
  end

  defp fetch(opts, :order) do
    case Keyword.fetch(opts, :order) do
      {:ok, order} = result when order in [:asc, :desc] -> result
      :error -> {:ok, :asc}
      {:ok, invalid} -> {:error, order: invalid}
    end
  end

  defp get_while(cron, datetime, fun, order) do
    cron
    |> stream(from: datetime, order: order)
    |> Stream.filter(fun)
    |> head()
  end

  defp head(%Stream{} = stream), do: stream |> Enum.take(1) |> head()

  defp head([]), do: :error

  defp head([item]), do: {:ok, item}

  defp from_naive!({:ok, %NaiveDateTime{} = datetime}), do: {:ok, from_naive!(datetime)}

  defp from_naive!(%NaiveDateTime{} = datetime), do: DateTime.from_naive!(datetime, "Etc/UTC")

  defp from_naive!(:error), do: :error

  defimpl Inspect do
    @spec inspect(Cron.t(), Inspect.Opts.t()) :: String.t()
    def inspect(cron, _opts), do: "#Cron<#{cron.expression}>"
  end

  defimpl String.Chars do
    @spec to_string(Cron.t()) :: String.t()
    def to_string(%Cron{} = cron), do: cron.expression
  end
end
