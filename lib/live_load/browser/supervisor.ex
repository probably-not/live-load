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
    case LiveLoad.SupUtils.find_child(supervisor, :connection) do
      connection when is_pid(connection) ->
        connection

      nil ->
        raise RuntimeError, """
        The connection could not be found under the given supervisor!

        The `LiveLoad.Browser.Supervisor.connection_pid!/1` function should
        only be called by `LiveLoad.Browser.Connection` implementations which
        implement the `child_spec/1` callback of the behaviour, allowing them to
        initialize a proper supervision tree for the browser connection.

        If the `child_spec/1` callback has not been implemented and your
        `LiveLoad.Browser.Connection` implementation requires the current PID of
        the connection process and it is not a named local process that can be
        accessed via the process name, this is an issue in the implementation and the
        implmentation must ensure that the `child_spec/1` callback returns a full
        child spec, or ensure that the implementation has a properly configured name.

        If your `LiveLoad.Browser.Connection` implementation does not require the
        current PID of the connection process and this function has not been called
        by your implementation's code, this may be an issue in `LiveLoad` itself,
        and should be reported to the maintainers.

        Please file issues at: https://github.com/probably-not/live-load/issues.
        """
    end
  end
end
