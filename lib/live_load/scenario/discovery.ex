defmodule LiveLoad.Scenario.Discovery do
  @moduledoc false
  # `LiveLoad.Scenario.Discovery` provides a simplistic discovery mechanism for all `LiveLoad.Scenario` modules in a project.
  # It's very basic - we simply loop over all of the compiled modules in the given app, extract the behaviours in the modules,
  # and check to see if our `LiveLoad.Scenario` module is in the list of behaviours.

  def resolve(single_scenario, list_of_scenarios, otp_app)

  def resolve(nil, nil, nil) do
    otp_app = Application.get_env(:live_load, :otp_app) || infer_otp_app()
    discover_scenarios(otp_app)
  end

  def resolve(nil, nil, otp_app) do
    discover_scenarios(otp_app)
  end

  def resolve(nil, list_of_scenarios, _otp_app) when is_list(list_of_scenarios) do
    Enum.filter(list_of_scenarios, &scenario?/1)
  end

  def resolve(single_scenario, _list_of_scenarios, _otp_app) when is_atom(single_scenario) do
    single_scenario
    |> List.wrap()
    |> Enum.filter(&scenario?/1)
  end

  defp discover_scenarios(nil) do
    raise ArgumentError, """
    `:otp_app` is required in order to automatically discover scenarios.

    The `:otp_app` value can either be set in the application config:

    ```elixir
    config: :live_load, otp_app: :my_app
    ```

    Or it can be passed directly to `LiveLoad.run/1`:

    ```elixir
    LiveLoad.run(otp_app: :my_app)
    ```

    Alternatively, you may pass a single specific scenario with `:scenario`,
    or a list of specific scenarios with `:scenarios`.
    """
  end

  defp discover_scenarios(otp_app) when is_atom(otp_app) do
    otp_app
    |> Application.spec(:modules)
    |> List.wrap()
    |> Enum.filter(&scenario?/1)
  end

  defp scenario?(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) do
      behaviours =
        :attributes
        |> mod.module_info()
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      LiveLoad.Scenario in behaviours
    else
      false
    end
  end

  defp scenario?(_mod) do
    false
  end

  defp infer_otp_app do
    if Code.ensure_loaded?(Mix.Project) and Mix.Project.get() do
      Mix.Project.config()[:app]
    end
  end
end
