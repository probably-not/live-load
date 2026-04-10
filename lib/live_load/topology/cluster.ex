defmodule LiveLoad.Topology.Cluster do
  @moduledoc false

  use Supervisor

  def start_link(_opts) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def start_flame_pool(supervisor, opts) do
    wrapped = Supervisor.child_spec({FLAME.Pool, opts}, id: :pool, restart: :temporary, significant: true)
    Supervisor.start_child(supervisor, wrapped)
  end

  @impl true
  def init(_opts) do
    Supervisor.init([], strategy: :one_for_one, auto_shutdown: :any_significant)
  end
end
