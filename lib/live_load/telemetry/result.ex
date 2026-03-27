defmodule LiveLoad.Telemetry.Result do
  @moduledoc """
  `LiveLoad.Telemetry.Result` defines the struct type for the results of a scenario's load test.

  It contains 4 fields:
  - `:total`: The total number of user processes
  - `:succeeded`: The number of user processes that succeeded running through the scenario
  - `:failed`: The number of user processes that failed to complete their scenario
  - `:sketches`: A map of `t:sketch_name/0` to [`:ddskerl.ddsketch/0`](https://hexdocs.pm/ddskerl/ddskerl.html#t:ddsketch/0) data structures.
  These sketches can be used by reporters to calculate metrics on the run itself.
  """

  @typedoc """
  One of the sketch names for sketches that are tracked while running the load test.
  """
  @type sketch_name() :: :scenario_duration_us

  @typedoc """
  One of the counter names for any counter that is tracked while running the load test.
  """
  @type counter_name() ::
          :liveview_disconnections
          | :liveview_reconnections
          | :liveview_canceled_loads
          | :liveview_navigations
          | :websocket_connections_opened
          | :websocket_connections_closed

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
    [:scenario_duration_us]
  end

  @doc false
  def counter_names do
    [
      :liveview_disconnections,
      :liveview_reconnections,
      :liveview_canceled_loads,
      :liveview_navigations,
      :websocket_connections_opened,
      :websocket_connections_closed
    ]
  end
end
