[
  {"lib/mix/tasks/init_playwright.ex", "Callback info about the Mix.Task behaviour is not available."},
  {"lib/mix/tasks/init_playwright.ex", "Function Mix.shell/0 does not exist."},
  # TODO: This looks like maybe a spec issue inside PlaywrightEx.
  # Maybe we can fix it at some point...
  {"lib/live_load/browser/connection/playwright.ex", "Function after_start/1 has no local return."},
  {"lib/live_load/browser/connection/playwright.ex", "The function call launch_browser will not succeed."},
  # TODO: This error is due to not handling `:amoc_dist` yet. It should be removed when we do.
  {"lib/live_load.ex", "The pattern can never match the type :ok | {:error, _}."}
]
