defmodule LiveLoad.Browser do
  @moduledoc """
  `LiveLoad.Browser` is the struct representing the browser abstraction that is used in a `LiveLoad.Scenario`.
  It wraps the given implementation of the `LiveLoad.Browser.Connection` behaviour. All operations on the browser
  instance are delegated to the `LiveLoad.Browser.Connection` implementation.

  `LiveLoad.Browser` is the top-level of the Browser hierarchy. For every node running a `LiveLoad.Scenario`, a
  single `LiveLoad.Browser` is created, and each user receives a clean, isolated `LiveLoad.Browser.Context` created
  via `LiveLoad.Browser.new_context/1`.

  For operations users can take on the context, see the `LiveLoad.Browser.Context` module.
  """

  alias __MODULE__
  alias LiveLoad.Browser.Connection

  @type t() :: %__MODULE__{
          connection: {Connection.t(), Connection.opts()},
          supervisor_pid: pid(),
          private: %{optional(atom()) => term()}
        }

  defstruct [:connection, :supervisor_pid, private: %{}]

  @doc """
  Delegates to the connection implementation on the browser and runs
  the `c:LiveLoad.Browser.Connection.drain_metrics/1` callback found on the implementation.
  """
  @spec drain_metrics(browser :: Browser.t()) :: :ok
  def drain_metrics(%Browser{connection: {mod, _opts}} = browser) do
    mod.drain_metrics(browser)
  end

  @doc """
  Delegates to the connection implementation on the browser and runs
  the `c:LiveLoad.Browser.Connection.new_context/1` callback found on the implementation.
  """
  @spec new_context(browser :: Browser.t()) :: {:ok, Browser.Context.t()} | {:error, term()}
  def new_context(%Browser{connection: {mod, _opts}} = browser) do
    mod.new_context(browser)
  end

  @doc """
  Set a value on the private field on the browser struct.
  This is useful for Connection implementations to add private data
  that they need access to while running.
  """
  @spec put_private(browser :: t(), key :: atom(), value :: term()) :: t
  def put_private(%Browser{private: private} = browser, key, value) when is_atom(key) do
    %{browser | private: Map.put(private, key, value)}
  end

  @doc false
  def run_hook(%Browser{connection: {mod, _opts}} = browser, hook) when is_atom(mod) and is_atom(hook) do
    apply(mod, hook, [browser])
  end
end
