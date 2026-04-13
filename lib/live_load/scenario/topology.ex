defmodule LiveLoad.Scenario.Topology do
  @moduledoc false

  use Supervisor

  alias LiveLoad.Browser
  alias LiveLoad.Telemetry

  def setup({browser_connection_adapter, browser_connection_opts, _collector_pid} = init_arg) do
    browser = %Browser{connection: {browser_connection_adapter, browser_connection_opts}}

    with {:ok, %Browser{} = browser} <- Browser.run_hook(browser, :before_start),
         {:ok, pid} when is_pid(pid) <-
           DynamicSupervisor.start_child(
             LiveLoad.Scenario.Topology.DynamicSupervisor,
             Supervisor.child_spec({__MODULE__, init_arg}, restart: :temporary)
           ),
         {:ok, %Browser{} = prepared_browser} <- prepare_browser(pid, browser) do
      :ok = connect_browser(pid, prepared_browser)
      {:ok, pid}
    end
  end

  def teardown(supervisor \\ __MODULE__) do
    browser = browser!()
    :ok = Browser.run_hook(browser, :before_stop)
    :ok = Supervisor.stop(supervisor)
    :ok = Browser.run_hook(browser, :after_stop)
  end

  defp prepare_browser(supervisor, %Browser{} = browser) do
    browser_supervisor_pid = browser_supervisor_pid!(supervisor)

    with {:ok, %Browser{} = browser} <-
           Browser.run_hook(%{browser | supervisor_pid: browser_supervisor_pid}, :after_start) do
      {:ok, tap(browser, &store_browser/1)}
    end
  end

  defp connect_browser(supervisor, %Browser{} = browser) do
    telemetry_listener_pid = telemetry_listener_pid!(supervisor)
    Telemetry.Listener.connect_browser(telemetry_listener_pid, browser)
  end

  def start_link({browser_connection_adapter, browser_connection_opts, collector_pid}) do
    Supervisor.start_link(__MODULE__, {browser_connection_adapter, browser_connection_opts, collector_pid},
      name: __MODULE__
    )
  end

  @impl true
  def init({browser_connection_adapter, browser_connection_opts, collector_pid}) do
    children = [
      Browser.Supervisor.child_spec(browser_connection_adapter, browser_connection_opts,
        id: :browser_supervisor,
        restart: :temporary,
        significant: true
      ),
      Supervisor.child_spec({Telemetry.Listener, collector_pid},
        id: :telemetry_listener,
        restart: :temporary,
        significant: true
      ),
      LiveLoad.Scenario.Topology.BrowserStore
    ]

    # Using the module as the name should be fine here. The topology of a scenario runs in an isolated node,
    # either under the amoc peer or the flame node running the distributed test. It should be unique to the node.
    Supervisor.init(children, strategy: :one_for_one, auto_shutdown: :any_significant)
  end

  @key {__MODULE__, :browser}

  def browser! do
    %Browser{} = :persistent_term.get(@key)
  end

  def clear_browser do
    :persistent_term.erase(@key)
  end

  defp store_browser(%Browser{} = browser) do
    :persistent_term.put(@key, browser)
  end

  defp browser_supervisor_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :browser_supervisor) do
      browser_supervisor when is_pid(browser_supervisor) -> browser_supervisor
      nil -> raise RuntimeError, "Scenario.Topology does not contain the browser_supervisor child process"
    end
  end

  def telemetry_listener_pid!(supervisor) do
    case LiveLoad.SupUtils.find_child(supervisor, :telemetry_listener) do
      telemetry_listener when is_pid(telemetry_listener) -> telemetry_listener
      nil -> raise RuntimeError, "Scenario.Topology does not contain the telemetry_listener child process"
    end
  end
end
