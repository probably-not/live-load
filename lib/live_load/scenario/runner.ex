defmodule LiveLoad.Scenario.Runner do
  @moduledoc false

  @behaviour :gen_statem

  alias LiveLoad.Scenario

  defmodule Data do
    @moduledoc false

    @type config() :: %{scenario_config: Scenario.config(), __config__: Scenario.internal_config()}

    @type t() :: %__MODULE__{
            ref: reference(),
            scenario: Scenario.t(),
            context: Scenario.Context.t(),
            user_id: Scenario.user_id(),
            config: config(),
            task_pid: pid() | nil,
            result: Scenario.user_result()
          }
    defstruct [:ref, :scenario, :context, :user_id, :config, :task_pid, :result]
  end

  @spec run(
          scenario :: module(),
          context :: Scenario.Context.t(),
          user_id :: Scenario.user_id(),
          config :: Data.config()
        ) :: Scenario.user_result()
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
          {^ref, :result, result} -> result
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
    :amoc_coordinator.add({data.scenario, :heartbeat}, data.user_id)

    {:next_state, :waiting_for_completion, %{data | task_pid: task.pid},
     [
       {{:timeout, :heartbeat}, data.config.__config__.heartbeat_timeout, :heartbeat},
       {:state_timeout, data.config.__config__.scenario_timeout, :scenario_timeout}
     ]}
  end

  def waiting_for_completion({:call, _from}, :wait, %Data{} = _data) do
    {:keep_state_and_data, :postpone}
  end

  def waiting_for_completion({:timeout, :heartbeat}, :heartbeat, %Data{} = data) do
    :amoc_coordinator.add({data.scenario, :heartbeat}, data.user_id)
    {:keep_state_and_data, [{{:timeout, :heartbeat}, data.config.__config__.heartbeat_timeout, :heartbeat}]}
  end

  def waiting_for_completion(:info, {ref, result}, %Data{} = data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, %{data | result: result}, [{{:timeout, :stop}, 0, :stop}]}
  end

  def waiting_for_completion(:info, {:DOWN, _ref, :process, _pid, reason}, %Data{} = data) do
    {:next_state, :done, %{data | result: {:error, reason}}, [{{:timeout, :stop}, 0, :stop}]}
  end

  def waiting_for_completion(:state_timeout, :scenario_timeout, %Data{} = data) do
    {:next_state, :done, %{data | result: {:error, :timeout}}, [{{:timeout, :stop}, 0, :stop}]}
  end

  def done({:timeout, :stop}, :stop, %Data{} = data) do
    Process.exit(data.task_pid, :kill)
    send(self(), {data.ref, :result, data.result})
    {:stop, :normal}
  end

  defp partitioned_async_nolink(scenario, context, user_id, config) do
    Task.Supervisor.async_nolink(
      {:via, PartitionSupervisor, {LiveLoad.Scenario.Runner.TaskSupervisor, user_id}},
      scenario,
      :run,
      [context, user_id, config]
    )
  end
end
