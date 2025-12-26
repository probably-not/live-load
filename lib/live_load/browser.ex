defmodule LiveLoad.Browser do
  @moduledoc """
  TODO: Let's document the LiveLoad.Browser module!
  """

  alias __MODULE__
  alias LiveLoad.Browser.Connection

  @type t() :: %__MODULE__{
          connection_mod: {Connection.t(), Connection.opts()},
          supervisor_pid: pid(),
          private: %{optional(atom()) => term()}
        }

  defstruct [:connection_mod, :supervisor_pid, private: %{}]

  @spec start_link(connection_mod :: Connection.t(), opts :: Keyword.t()) :: {:ok, t()} | {:error, term()}
  def start_link(connection_mod, opts \\ []) when is_atom(connection_mod) do
    browser = %Browser{connection_mod: {connection_mod, opts}}

    case Browser.Supervisor.start_link(connection_mod, opts) do
      {:ok, pid} when is_pid(pid) -> {:ok, %{browser | supervisor_pid: pid}}
      {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, %{browser | supervisor_pid: pid}}
      {:error, _reason} = error -> error
    end
  end

  @spec stop(browser :: t(), reason :: term(), timeout :: timeout()) :: :ok
  def stop(%Browser{} = browser, reason \\ :normal, timeout \\ :infinity) do
    Supervisor.stop(browser.supervisor_pid, reason, timeout)
  end

  @spec put_private(browser :: t(), key :: atom(), value :: term()) :: t
  def put_private(%Browser{private: private} = browser, key, value) when is_atom(key) do
    %{browser | private: Map.put(private, key, value)}
  end
end
