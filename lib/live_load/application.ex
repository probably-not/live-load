defmodule LiveLoad.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {PartitionSupervisor, child_spec: Task.Supervisor, name: LiveLoad.Scenario.Runner.TaskSupervisor},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: LiveLoad.Cluster.DynamicSupervisor}
    ]

    opts = [strategy: :one_for_one, name: LiveLoad.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
