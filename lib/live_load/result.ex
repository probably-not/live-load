defmodule LiveLoad.Result do
  @moduledoc """
  `LiveLoad.Result` defines the struct type for the results of a scenario's load test.

  It contains 4 fields:
  - `:total`: The total number of user processes
  - `:succeeded`: The number of user processes that succeeded running through the scenario
  - `:failed`: The number of user processes that failed to complete their scenario
  - `:sketches`: A map of `t:sketch_name/0` to [`:ddskerl.ddsketch/0`](https://hexdocs.pm/ddskerl/ddskerl.html#t:ddsketch/0) data structures.
  - `:counters`: A map of `t:counter_name/0` to `t:non_neg_integer/0`.
  These sketches can be used by reporters to calculate metrics on the run itself.
  """

  @typedoc """
  One of the sketch names for sketches that are tracked while running the load test.

  Sketch names can take 2 forms:
  - `name :: atom()`: An aggregated sketch
  - `{name :: atom(), dimension :: String.t()}`: A sketch broken down by a dimension to allow drilldowns
  """
  @type sketch_name() ::
          :scenario_duration_us
          | :liveview_connection_duration_us
          | {:liveview_connection_duration_us, href :: String.t()}
          | :liveview_reconnection_duration_us
          | {:liveview_reconnection_duration_us, href :: String.t()}
          | :liveview_page_loading_duration_us
          | {:liveview_page_loading_duration_us, kind :: String.t()}
          | :liveview_loading_class_duration_us
          | {:liveview_loading_class_duration_us, class :: String.t()}
          | :http_request_duration_us
          | {:http_request_duration_us, resource_type :: String.t()}
          | :http_request_ttfb_us
          | {:http_request_ttfb_us, resource_type :: String.t()}
          | :http_request_dns_us
          | {:http_request_dns_us, resource_type :: String.t()}
          | :http_request_connect_us
          | {:http_request_connect_us, resource_type :: String.t()}
          | :http_request_tls_us
          | {:http_request_tls_us, resource_type :: String.t()}
          | :websocket_frame_sent_bytes
          | {:websocket_frame_sent_bytes, url :: String.t()}
          | :websocket_frame_received_bytes
          | {:websocket_frame_received_bytes, url :: String.t()}

  @typedoc """
  One of the counter names for any counter that is tracked while running the load test.

  Counter names can take 2 forms:
  - `name :: atom()`: An aggregated counter
  - `{name :: atom(), dimension :: String.t()}`: A counter broken down by a dimension to allow drilldowns
  """
  @type counter_name() ::
          :liveview_navigations
          | :liveview_disconnections
          | {:liveview_disconnections, href :: String.t()}
          | :liveview_reconnections
          | {:liveview_reconnections, href :: String.t()}
          | :liveview_canceled_loads
          | {:liveview_canceled_loads, kind :: String.t()}
          | :websocket_connections_opened
          | {:websocket_connections_opened, url :: String.t()}
          | :websocket_connections_closed
          | {:websocket_connections_closed, url :: String.t()}

  @type t() :: %__MODULE__{
          total: pos_integer(),
          succeeded: non_neg_integer(),
          failed: non_neg_integer(),
          sketches: %{sketch_name() => :ddskerl.ddsketch()},
          counters: %{counter_name() => non_neg_integer()}
        }

  @enforce_keys [:total, :succeeded, :failed, :sketches, :counters]
  defstruct [:total, :succeeded, :failed, :sketches, :counters]

  @doc false
  def sketch_names do
    [
      :scenario_duration_us,
      :liveview_connection_duration_us,
      :liveview_reconnection_duration_us,
      :liveview_page_loading_duration_us,
      :liveview_loading_class_duration_us,
      :http_request_duration_us,
      :http_request_ttfb_us,
      :http_request_dns_us,
      :http_request_connect_us,
      :http_request_tls_us,
      :websocket_frame_sent_bytes,
      :websocket_frame_received_bytes
    ]
  end

  @doc false
  def counter_names do
    [
      :liveview_navigations,
      :liveview_disconnections,
      :liveview_reconnections,
      :liveview_canceled_loads,
      :websocket_connections_opened,
      :websocket_connections_closed
    ]
  end
end
