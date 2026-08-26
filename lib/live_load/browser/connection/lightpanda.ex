defmodule LiveLoad.Browser.Connection.Lightpanda do
  @moduledoc """
  An implementation of `LiveLoad.Browser.Connection` that uses the `Mint.WebSocket` library to communicate with a Lightpanda CDP instance.

  This implementation is experimental as not everything is implemented on Lightpanda. The details of unsupported features and metrics can
  be found through the `LiveLoad.Browser.Connection.Lightpanda.metadata/0` function. These details will also be present on any `LiveLoad.Result`
  generated using this connection implementation.
  """

  use LiveLoad.Browser.Connection

  alias LiveLoad.Browser.Connection.Lightpanda.Supervisor

  @typedoc """
  Options passed in to the connection for Lightpanda.

  ## Options
  - `:command_timeout` (`t:timeout/0`): A timeout for commands sent to the Lightpanda instance.
  """
  @type connection_option() :: {:command_timeout, timeout()}

  @impl true
  @doc false
  def metadata do
    %{
      adapter: inspect(__MODULE__),
      unsupported_metrics: %{
        "http_request_duration_us" => :estimated,
        "http_request_ttfb_us" => :estimated,
        "http_request_dns_us" => :unsupported,
        "http_request_connect_us" => :unsupported,
        "http_request_tls_us" => :unsupported,
        "websocket" => :instrumented
      },
      unsupported_features: %{
        "local_storage" => :instrumented,
        "session_storage" => :instrumented,
        "indexed_db" => :unsupported,
        "drag_and_drop" => :instrumented
      }
    }
  end

  @impl true
  @doc false
  defdelegate child_spec(opts), to: Supervisor

  # TODO: I'm currently using the same values for the sizing as I used on Playwright.
  # According to Lightpanda's documentation, these instances should be a lot less resource
  # intensive, meaning that I should be able to drop these values down to much lower numbers
  # and allow more instances per node raised for the load test, lowering costs.

  @impl true
  @doc false
  def browser_contexts_per_core, do: 2

  @impl true
  @doc false
  def browser_memory_usage_bytes, do: 250 * 1024 * 1024

  @impl true
  @doc false
  def context_memory_usage_bytes, do: 150 * 1024 * 1024

  ## TODO: Implement all of the functionality...
end
