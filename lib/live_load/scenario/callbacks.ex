defmodule LiveLoad.Scenario.Callbacks do
  @moduledoc false

  alias LiveLoad.Browser
  alias LiveLoad.Scenario

  def init(scenario) do
    iteration_timeout = :amoc_config.get(:iteration_timeout)
    scenario_duration = :amoc_config.get(:scenario_duration)
    opts = :amoc_config.get(:scenario_config_opts)
    browser = Scenario.Topology.browser!()

    with {:ok, scenario_config} <- scenario.config(opts) do
      {:ok,
       %{
         scenario_config: scenario_config,
         __config__: %{
           browser: browser,
           iteration_timeout: iteration_timeout,
           scenario_duration: scenario_duration
         }
       }}
    end
  end

  def start(scenario, user_id, opts) do
    case Browser.new_context(opts.__config__.browser) do
      {:ok, %Browser.Context{} = browser_context} ->
        try do
          Scenario.Runner.run(scenario, Scenario.Context.new(browser_context), user_id, opts)
        after
          Browser.Context.stop(browser_context)
        end

      {:error, reason} ->
        raise RuntimeError, """
        Failed to initialize the browser context for #{inspect(scenario)} with reason: #{inspect(reason)}
        """
    end
  end

  def terminate(_scenario, _opts) do
    Scenario.Topology.teardown()
  end
end
