defmodule LiveLoad.Browser.Connection.Lightpanda.Supervisor do
  @moduledoc false

  use Supervisor

  alias LiveLoad.Browser.Connection.Lightpanda.Validator

  def start_link(opts) do
    if not Code.ensure_loaded?(Mint.WebSocket) do
      raise RuntimeError, """
      Using `LiveLoad.Browser.Connection.Lightpanda` browser implementation requires
      `{:mint_web_socket, "~> 1.0"}` in your application dependencies."
      """
    end

    validations = [
      :lightpanda_cli_path,
      name: __MODULE__,
      lightpanda_version: lightpanda_version_from_env(),
      startup_timeout: 1000
    ]

    opts = Keyword.validate!(opts, validations)

    {name, opts} = Keyword.pop!(opts, :name)
    {timeout, opts} = Keyword.pop!(opts, :startup_timeout)
    {lightpanda_version, opts} = Keyword.pop!(opts, :lightpanda_version)

    {lightpanda_cli_path, _opts} =
      Keyword.pop_lazy(opts, :lightpanda_cli_path, fn ->
        Validator.validate!(lightpanda_version)
      end)

    Supervisor.start_link(__MODULE__, {lightpanda_cli_path, timeout}, name: name)
  end

  @impl true
  def init({lightpanda_cli_path, timeout}) do
    children = [
      {LiveLoad.Browser.Connection.Lightpanda.PortManager,
       [
         name: __MODULE__.Lightpanda,
         executable: lightpanda_cli_path,
         timeout: timeout
       ]},
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: __MODULE__.BrowserContextSupervisor}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @default_lightpanda_version "0.3.6"
  def lightpanda_version_from_env do
    Application.get_env(:live_load, :lightpanda_version, @default_lightpanda_version)
  end
end
