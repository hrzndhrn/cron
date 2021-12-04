# Cron
[![Hex.pm: version](https://img.shields.io/hexpm/v/cron.svg?style=flat-square)](https://hex.pm/packages/cron)
[![GitHub: CI status](https://img.shields.io/github/workflow/status/hrzndhrn/cron/CI?style=flat-square)](https://github.com/hrzndhrn/cron/actions)
[![Coveralls: coverage](https://img.shields.io/coveralls/github/hrzndhrn/cron?style=flat-square)](https://coveralls.io/github/hrzndhrn/cron)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://github.com/hrzndhrn/cron/blob/main/LICENSE.md)

Cron parses cron expressions and calculates execution timings.

## Installation

The package can be installed by adding `cron` to your list of dependencies in
`mix.exs`:

```elixir
def deps do
  [
    {:cron, "~> 0.1"}
  ]
end
```

The [documentation](https://hexdocs.pm/cron) can be found on [hexdocs](https://hexdocs.pm/).

## Usage

`Cron` accepts cron expressions with 6 fields (including seconds) and 5 fields.
All functions are working with `NaiveDateTime` and `DateTime` that are using the
`Calendar.ISO`. `DateTime`s must use the time zone `Etc/UTC`.

Calculating the next execution datetime:
```elixir
iex> {:ok, cron} = Cron.new("0 0 * * FRI") # At 00:00 on Friday.
iex> Cron.next(cron)
~N[2021-12-03 00:00:00]
iex> Cron.next(cron, ~U[2021-12-03 00:00:00Z])
~U[2021-12-10 00:00:00Z]
```

Calculating the previous execution datetime:
```elixir
iex> {:ok, cron} = Cron.new("0 12 */2 * *") # At 12:00 on every 2nd day-of-month.
iex> Cron.previous(cron)
~N[2021-12-31 12:00:00]
iex> Cron.previous(cron, ~U[2021-12-31 12:00:00Z])
~U[2021-12-29 12:00:00Z]
```

Calculating the milliseconds until the next execution datetime:
```elixir
iex> cron = Cron.new!("22 44 12 * * *") # At 12:44:22.
iex> Cron.until(cron)
20256672
iex> Cron.until(cron, ~U[2022-01-01 12:44:11.123Z])
10877
```

The day can be specified by two fields, the `day` field and the `day of week`
field. If both fields are not set to `*`, the triggered datetimes are the union
of both restrictions. The expression `0 0 0 5 * MON` will be triggered at
00:00:00 on the 5th day of a month *and* on every Monday.

Calculating the next 5 execution datetimes:
```elixir
iex> cron = Cron.new!("0 0 0 5 * MON") # See the description above.
iex> stream = Cron.stream(cron, from: ~N[2022-01-01 00:00:00])
iex> Enum.take(stream, 5)
[
  ~N[2022-01-03 00:00:00],
  ~N[2022-01-05 00:00:00],
  ~N[2022-01-10 00:00:00],
  ~N[2022-01-17 00:00:00],
  ~N[2022-01-24 00:00:00]
]
```

Detecting the first day of a month that is a Monday:
```elixir
iex> cron = Cron.new!("0 0 0 1-7 * *") # At 00:00:00 on the first seven days of a month
iex> Cron.next_while(cron, fn datetime -> Date.day_of_week(datetime) == 1 end)
{:ok, ~N[2021-12-06 00:00:00]}
```

## Resources

* http://crontab.org/

* https://en.wikipedia.org/wiki/Cron

* https://crontab.guru/

* https://cronjob.xyz/
