defmodule LiveLoad.Browser.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(connection_mod, connection_args \\ []) do
    Supervisor.start_link(__MODULE__, {connection_mod, connection_args})
  end

  def child_spec(connection_mod, connection_args \\ [], supervisor_opts \\ []) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [connection_mod, connection_args]},
      type: :supervisor
    }

    Supervisor.child_spec(default, supervisor_opts)
  end

  @impl Supervisor
  def init({connection_mod, connection_args}) do
    children = [
      Supervisor.child_spec({connection_mod, connection_args}, id: :connection)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def connection_pid!(supervisor) do
    case find_child(supervisor, :connection) do
      connection when is_pid(connection) ->
        connection

      nil ->
        raise RuntimeError, """
        The connection could not be found under the given supervisor!
        This is a critical issue and should be reported to the maintainers.

        Please file issues at: https://github.com/probably-not/live-load/issues.
        """
    end
  end

  defp find_child(supervisor, child_id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find(fn
      {^child_id, pid, _type, _modules} when is_pid(pid) -> true
      _ -> false
    end)
    |> then(fn
      {^child_id, pid, _type, _modules} when is_pid(pid) -> pid
      _other -> nil
    end)
  end
end
