Code.require_file("test/cron_case.ex")

max_runs = if System.get_env("CI"), do: 1_000_000, else: 1_000
Application.put_env(:stream_data, :max_runs, max_runs)

ExUnit.start()
