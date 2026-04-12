defmodule LiveLoad.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: LiveLoad.Registry},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: LiveLoad.Topology.DynamicSupervisor},
      {DynamicSupervisor, name: LiveLoad.Scenario.Topology.DynamicSupervisor},
      {PartitionSupervisor, child_spec: Task.Supervisor, name: LiveLoad.Scenario.Runner.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: LiveLoad.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
