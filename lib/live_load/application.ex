defmodule LiveLoad.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: LiveLoad.Scenario.Runner.TaskSupervisor}
    ]

    opts = [strategy: :one_for_one, name: LiveLoad.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
