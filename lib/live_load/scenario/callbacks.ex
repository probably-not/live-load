defmodule LiveLoad.Scenario.Callbacks do
  @moduledoc false

  alias LiveLoad.Browser
  alias LiveLoad.Scenario
  alias LiveLoad.Scenario.Throttle

  require Logger

  def init(scenario) do
    iteration_timeout = :amoc_config.get(:iteration_timeout)
    scenario_duration = :amoc_config.get(:scenario_duration)
    opts = :amoc_config.get(:scenario_config_opts)
    browser = Scenario.Topology.browser!()

    with {:ok, scenario_config} <- scenario.config(opts),
         throttles = scenario.throttles(scenario_config),
         {:ok, validated_throttles} <- validate_throttles(throttles),
         :ok <- start_throttles(validated_throttles) do
      {:ok,
       %{
         scenario_config: scenario_config,
         __config__: %{
           browser: browser,
           iteration_timeout: iteration_timeout,
           scenario_duration: scenario_duration,
           throttle_names: MapSet.new(validated_throttles, & &1.name)
         }
       }}
    end
  end

  def start(scenario, user_id, opts) do
    case Browser.new_context(opts.__config__.browser) do
      {:ok, %Browser.Context{} = browser_context} ->
        try do
          Scenario.Runner.run(
            scenario,
            Scenario.Context.new(browser_context, opts.__config__.throttle_names),
            user_id,
            opts
          )
        after
          case safe_stop_context(browser_context) do
            {:error, reason} ->
              Logger.error([
                "[LiveLoad.Scenario.Callbacks] Failed to stop browser context: ",
                Exception.format_exit(reason)
              ])

            _ ->
              :ok
          end
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

  defp safe_stop_context(%Browser.Context{} = browser_context) do
    Browser.Context.stop(browser_context)
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp validate_throttles(throttles) do
    Enum.reduce_while(throttles, {:ok, []}, fn throttle, {:ok, valid} ->
      case Throttle.validate(throttle) do
        {:ok, throttle} -> {:cont, {:ok, [throttle | valid]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp start_throttles(throttles) do
    Enum.reduce_while(throttles, :ok, fn throttle, :ok ->
      name = Throttle.name(throttle)
      config = Throttle.to_amoc_config(throttle)

      with {:ok, result} <- :amoc_throttle.start(name, config),
           :ok <- maybe_add_ramp_to_throttle(result, name, throttle) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp maybe_add_ramp_to_throttle(:already_started, _name, _throttle) do
    # When we get `:already_started`, we can probably assume that the throttle has been set and the
    # ramp (if any) has been set, since someone else got `:started` before us.
    :ok
  end

  defp maybe_add_ramp_to_throttle(:started, name, throttle) do
    if ramp_up = Throttle.to_amoc_gradual_plan(throttle) do
      :amoc_throttle.change_rate_gradually(name, ramp_up)
    else
      :ok
    end
  end
end
