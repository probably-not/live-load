defmodule LiveLoad.Scenario.Runner do
  @moduledoc false

  @behaviour :gen_statem

  alias LiveLoad.Scenario

  @spec run(scenario :: module(), user_id :: Scenario.user_id(), config :: Scenario.config()) :: Scenario.user_result()
  def run(scenario, user_id, opts) do
    {:ok, pid} = :gen_statem.start_link(__MODULE__, {scenario, user_id, opts}, [])
    :gen_statem.call(pid, :wait, :infinity)
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init({scenario, user_id, opts}) do
    {:ok, :initializing, %{user_id: user_id, opts: opts, scenario: scenario}, {:next_event, :internal, :initializing}}
  end

  def initializing(:internal, :initializing, data) do
    Task.Supervisor.async_nolink(LiveLoad.Scenario.Runner.TaskSupervisor, data.scenario, :run, [
      data.user_id,
      data.opts.scenario_config
    ])

    :amoc_coordinator.add({data.scenario, :heartbeat}, data.user_id)

    {:next_state, :waiting_for_completion, data,
     [{{:timeout, :heartbeat}, data.opts.__config__.heartbeat_timeout, :heartbeat}]}
  end

  def waiting_for_completion({:call, _from}, :wait, _data) do
    {:keep_state_and_data, :postpone}
  end

  def waiting_for_completion({:timeout, :heartbeat}, :heartbeat, data) do
    :amoc_coordinator.add({data.scenario, :heartbeat}, data.user_id)
    {:keep_state_and_data, [{{:timeout, :heartbeat}, data.opts.__config__.heartbeat_timeout, :heartbeat}]}
  end

  def waiting_for_completion(:info, {ref, result}, data) do
    Process.demonitor(ref, [:flush])
    {:next_state, :done, {data, result}, [{{:timeout, :stop}, 0, :stop}]}
  end

  def waiting_for_completion(:info, {:DOWN, _ref, :process, _pid, reason}, data) do
    {:next_state, :done, {data, {:error, reason}}, [{{:timeout, :stop}, 0, :stop}]}
  end

  def done({:timeout, :stop}, :stop, _data) do
    {:stop, :normal}
  end

  def done({:call, from}, :wait, {_data, result}) do
    :gen_statem.reply(from, result)
    :keep_state_and_data
  end
end
