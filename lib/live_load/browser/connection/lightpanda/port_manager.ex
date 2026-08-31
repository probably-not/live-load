defmodule LiveLoad.Browser.Connection.Lightpanda.PortManager do
  @moduledoc false

  @behaviour :gen_statem

  @max_startup_tries 20

  def cdp_endpoint(server, timeout \\ to_timeout(second: 10)) do
    :gen_statem.call(server, :cdp_endpoint, timeout)
  end

  defmodule Data do
    @moduledoc false

    @type t() :: %__MODULE__{
            os_pid: integer(),
            port_pid: pid(),
            executable: Path.t(),
            uri: URI.t()
          }

    defstruct [:os_pid, :port_pid, :executable, :uri]

    def new(executable) do
      %__MODULE__{executable: executable}
    end
  end

  def child_spec(init_args, child_opts \\ []) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [init_args]}
    }

    Supervisor.child_spec(default, child_opts)
  end

  def start_link(opts) do
    validations = [:executable, timeout: 1000]
    opts = Keyword.validate!(opts, validations)
    {timeout, opts} = Keyword.pop!(opts, :timeout)
    {executable, _opts} = Keyword.pop!(opts, :executable)
    :gen_statem.start_link(__MODULE__, executable, timeout: timeout)
  end

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(executable) do
    {:ok, :initializing, Data.new(executable), [{:next_event, :internal, :initialize_port}]}
  end

  def initializing(:internal, :initialize_port, %Data{} = data) do
    # TODO: I should probably make sure that I can pass through different ports and connection counts.
    # This is "good enough" for experimenting with Lightpanda now.
    args =
      [
        data.executable,
        "serve",
        "--host",
        "127.0.0.1",
        "--port",
        "9222",
        "--cdp-max-connections",
        "1024"
      ]

    uri = URI.new!("http://127.0.0.1:9222")

    result = :exec.run_link(Enum.join(args, " "), [{:env, [:clear]}, {:kill_timeout, 10}, :stdout, :stderr])

    case result do
      {:ok, port_pid, os_pid} when is_pid(port_pid) and is_integer(os_pid) ->
        {:next_state, :pending, %{data | os_pid: os_pid, port_pid: port_pid, uri: uri},
         [{{:timeout, :ready?}, 10, {:ready?, 0}}]}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def pending({:timeout, :ready?}, {:ready?, try_count}, %Data{}) when try_count > @max_startup_tries do
    {:stop, :too_many_startup_retries}
  end

  def pending({:timeout, :ready?}, {:ready?, try_count}, %Data{} = data) do
    url = data.uri |> URI.append_path("/json/version") |> URI.to_string()

    case :httpc.request(:get, {String.to_charlist(url), []}, [], body_format: :binary) do
      {:ok, {{_, 200, _}, _, _body}} -> {:next_state, :started, data}
      # TODO: Log issues somewhere
      {:ok, {{_, _status, _}, _, _}} -> {:keep_state_and_data, [{{:timeout, :ready?}, 10, {:ready?, try_count + 1}}]}
      {:error, _reason} -> {:keep_state_and_data, [{{:timeout, :ready?}, 10, {:ready?, try_count + 1}}]}
    end
  end

  def pending(_event, _msg, _data) do
    {:keep_state_and_data, [:postpone]}
  end

  def started({:call, from}, :cdp_endpoint, %Data{uri: uri}) do
    :gen_statem.reply(from, uri)
    :keep_state_and_data
  end

  # TODO: Logging needs to be... better
  def started(:info, {:stdout, os_pid, output}, %Data{os_pid: os_pid}) do
    IO.write(output)
    :keep_state_and_data
  end

  def started(:info, {:stderr, os_pid, output}, %Data{os_pid: os_pid}) do
    IO.write(:stderr, output)
    :keep_state_and_data
  end
end
