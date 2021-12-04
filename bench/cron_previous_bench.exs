defmodule CronPreviousBench do
  use BencheeDsl.Benchmark

  config time: 10

  inputs %{
    "secondly" => Cron.new!("* * * * * *"),
    "every 2 minutes" => Cron.new!("0 */2 * * * *"),
    "first day in month" => Cron.new!("0 0 0 1 * *"),
    "leap year" => Cron.new!("0 0 0 29 2 *")
  }

  @datetime ~N[2022-02-10 12:30:55]

  job previous(cron) do
    Cron.previous(cron, @datetime)
  end
end
