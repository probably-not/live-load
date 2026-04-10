defmodule LiveLoad.Scenario.Runner do
  @moduledoc false

  @behaviour :gen_statem

  alias LiveLoad.Scenario

  require LiveLoad.Scenario.Context

  defmodule Data do
    @moduledoc false

    @type config() :: %{scenario_config: Scenario.config(), __config__: Scenario.internal_config()}

    @type t() :: %__MODULE__{
            ref: reference(),
            scenario: Scenario.t(),
            context: Scenario.Context.t(),
            user_id: Scenario.user_id(),
            config: config(),
            task_pid: pid() | nil
          }
    defstruct [:ref, :scenario, :context, :user_id, :config, :task_pid]
  end

  @spec run(
          scenario :: module(),
          context :: Scenario.Context.t(),
          user_id :: Scenario.user_id(),
          config :: Data.config()
        ) :: :ok | no_return()
  def run(scenario, context, user_id, config) do
    ref = make_ref()

    # A trick learned from the AMoC docs:
    # Instead of creating a new process and linking it,
    # we simply take over the current process with `:gen_statem.enter_loop`.
    # Since AMoC raises processes properly, this means that the `:gen_statem`
    # engine can take over the current process and run the loop internally,
    # and we can avoid creating one of the extra processes per user.
    try do
      :gen_statem.enter_loop(
        __MODULE__,
        [],
        :initializing,
        %Data{ref: ref, user_id: user_id, config: config, scenario: scenario, context: context},
        [
          {:next_event, :internal, :initializing}
        ]
      )
    catch
      :exit, :normal ->
        receive do
          {^ref, :failure, %Scenario.Error{} = error} ->
            raise error

          {^ref, :failure, reason} when is_exception(reason) ->
            raise reason

          {^ref, :failure, :timeout} ->
            raise RuntimeError, """
            Failed to complete the scenario within the iteration timeout.

            The configured timeout per iteration of this scenario is #{config.__config__.iteration_timeout},
            meaning each iteration of the scenario must complete before this timeout occurs.
            """

          {^ref, :failure, reason} ->
            raise RuntimeError, "Failed to complete the iteration with reason: #{inspect(reason)}"
        after
          0 -> :ok
        end
    end
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(_) do
    raise "unreachable"
  end

  def initializing(:internal, :initializing, %Data{} = data) do
    %Task{} = task = partitioned_async_nolink(data.scenario, data.context, data.user_id, data.config.scenario_config)

    {
      :next_state,
      :looping,
      %{data | task_pid: task.pid},
      [
        {{:timeout, :iteration_timeout}, data.config.__config__.iteration_timeout, :iteration_timeout},
        {{:timeout, :scenario_duration}, data.config.__config__.scenario_duration, :scenario_duration_expired}
      ]
    }
  end

  def looping(:info, {ref, %Scenario.Context{} = context}, %Data{} = data) when Scenario.Context.failed?(context) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:completed, context}}]}
  end

  def looping(:info, {ref, %Scenario.Context{} = context}, %Data{} = data) when Scenario.Context.halted?(context) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:completed, context}}]}
  end

  def looping(:info, {ref, %Scenario.Context{} = context}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    %Task{} = task = partitioned_async_nolink(data.scenario, context, data.user_id, data.config.scenario_config)

    {
      :keep_state,
      %{data | task_pid: task.pid, context: context},
      [{{:timeout, :iteration_timeout}, data.config.__config__.iteration_timeout, :iteration_timeout}]
    }
  end

  def looping(:info, {ref, {:error, reason}}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:failed, reason}}]}
  end

  def looping(:info, {ref, invalid_return_value}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:failed, {:invalid_return_value, invalid_return_value}}}]}
  end

  def looping(:info, {:DOWN, _ref, :process, _pid, reason}, %Data{} = data) do
    {:next_state, :done, data, [{:next_event, :internal, {:crash, reason}}]}
  end

  def looping({:timeout, :iteration_timeout}, :iteration_timeout, %Data{} = data) do
    {:next_state, :done, data, [{:next_event, :internal, :timeout}]}
  end

  def looping({:timeout, :scenario_duration}, :scenario_duration_expired, %Data{} = data) do
    {:next_state, :waiting_for_final_iteration, data}
  end

  def waiting_for_final_iteration(:info, {ref, %Scenario.Context{} = context}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:completed, context}}]}
  end

  def waiting_for_final_iteration(:info, {ref, {:error, reason}}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:failed, reason}}]}
  end

  def waiting_for_final_iteration(:info, {ref, invalid_return_value}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, data, [{:next_event, :internal, {:failed, {:invalid_return_value, invalid_return_value}}}]}
  end

  def waiting_for_final_iteration(:info, {:DOWN, _ref, :process, _pid, reason}, %Data{} = data) do
    {:next_state, :done, data, [{:next_event, :internal, {:crash, reason}}]}
  end

  def waiting_for_final_iteration({:timeout, :iteration_timeout}, :iteration_timeout, %Data{} = data) do
    {:next_state, :done, data, [{:next_event, :internal, :timeout}]}
  end

  def done(:internal, {:completed, %Scenario.Context{} = context}, %Data{} = data) do
    check_context_for_failure(data.ref, context)
    {:stop, :normal}
  end

  def done(:internal, {:failed, reason}, %Data{} = data) do
    report_failure(data.ref, reason)
    {:stop, :normal}
  end

  def done(:internal, {:crash, reason}, %Data{} = data) do
    report_failure(data.ref, reason)
    {:stop, :normal}
  end

  def done(:internal, :timeout, %Data{} = data) do
    Process.exit(data.task_pid, :kill)
    report_failure(data.ref, :timeout)
    {:stop, :normal}
  end

  defp check_context_for_failure(ref, context)
  defp check_context_for_failure(_ref, %Scenario.Context{error: nil}), do: :ok
  defp check_context_for_failure(ref, %Scenario.Context{error: error}), do: report_failure(ref, error)

  defp report_failure(ref, reason), do: send(self(), {ref, :failure, reason})

  defp partitioned_async_nolink(scenario, context, user_id, config) do
    Task.Supervisor.async_nolink(
      {:via, PartitionSupervisor, {LiveLoad.Scenario.Runner.TaskSupervisor, user_id}},
      scenario,
      :run,
      [context, user_id, config]
    )
  end
end
