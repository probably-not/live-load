defmodule LiveLoad.Browser do
  @moduledoc """
  TODO: Let's document the LiveLoad.Browser module!
  """

  alias __MODULE__
  alias LiveLoad.Browser.Connection

  @type t() :: %__MODULE__{
          connection: {Connection.t(), Connection.opts()},
          supervisor_pid: pid(),
          private: %{optional(atom()) => term()}
        }

  defstruct [:connection, :supervisor_pid, private: %{}]

  @spec start_link(connection_mod :: Connection.t(), opts :: Keyword.t()) :: {:ok, t()} | {:error, term()}
  def start_link(connection_mod, opts \\ []) when is_atom(connection_mod) do
    browser = run_hook(%Browser{connection: {connection_mod, opts}}, :before_start)

    case Browser.Supervisor.start_link(connection_mod, opts) do
      {:ok, pid} when is_pid(pid) ->
        {:ok, run_hook(%{browser | supervisor_pid: pid}, :after_start)}

      {:error, {:already_started, pid}} when is_pid(pid) ->
        {:ok, run_hook(%{browser | supervisor_pid: pid}, :after_start)}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Delegates to the connection implementation on the browser and runs the `new_context/1` callback found on the implementation.
  """
  @spec new_context(browser :: Browser.t()) :: {:ok, Context.t()} | {:error, term()}
  def new_context(%Browser{connection: {mod, _opts}} = browser) do
    mod.new_context(browser)
  end

  @spec stop(browser :: t(), reason :: term(), timeout :: timeout()) :: :ok
  def stop(%Browser{} = browser, reason \\ :normal, timeout \\ :infinity) do
    browser = run_hook(browser, :before_stop)
    Supervisor.stop(browser.supervisor_pid, reason, timeout)
    run_hook(browser, :after_stop)
  end

  @spec put_private(browser :: t(), key :: atom(), value :: term()) :: t
  def put_private(%Browser{private: private} = browser, key, value) when is_atom(key) do
    %{browser | private: Map.put(private, key, value)}
  end

  defp run_hook(%Browser{connection: {mod, _opts}} = browser, hook) when is_atom(mod) and is_atom(hook) do
    apply(mod, hook, [browser])
  end
end
