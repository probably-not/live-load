defmodule LiveLoad.Result do
  @moduledoc """
  `LiveLoad.Result` defines the summarized result of a full distributed load test.
  This result is a compact, serializable representation of all of the metrics collected while the load test was running across all of the nodes.
  It can be used by reporters in order to render reports of what occured during the entirety of a load test.

  The result structure is made up of a pre-computed set of quantiles from 0-100, along with dimensional breakdowns of different metrics by various dimensions,
  time series data that can show all of the collected data on a timeline of the entire load test, and per-node breakdowns of each metric to allow pinning down
  the data from individual nodes that ran the load test.

  This structure is built with the following notes in mind:
  - Semi-compact: it is exploded to allow easy access to all of the dimensions and time series buckets,
    but is compacted into structures of arrays with indices in the metadata instead of large objects.
  - JSON serializable: Reporters can be built with any language that can read the serialized result.
  - Minimal understanding of internals: Reporters don't need to know much about the internals of LiveLoad.
    The `LiveLoad.Result` contains all of the necessary information already fully calculated, allowing any reporter to do whatever they want with it.
  """

  alias LiveLoad.Scenario
  alias LiveLoad.Telemetry

  require LiveLoad.JSON

  defmodule Users do
    @moduledoc """
    Overall summary of users that completed a scenario run.
    """

    @type t() :: %__MODULE__{
            total: non_neg_integer(),
            succeeded: non_neg_integer(),
            failed: non_neg_integer()
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:total, :succeeded, :failed]
  end

  defmodule PrecomputedQuantiles do
    @moduledoc """
    Precomputed compact quantile curve materialized from an underlying [`:ddskerl.ddsketch/0`](https://hexdocs.pm/ddskerl/ddskerl.html#t:ddsketch/0)
    collected by the LiveLoad scenario telemetry pipeline.

    - `:values` is a list of 101 numbers — the quantile function evaluated at 1% intervals from 0.00 to 1.00.
    Quantile points are listed in the parent `LiveLoad.Result` `:quantile_points` field.
    - `:count` is the number of observations that occured on the sketch.
    - `:sum` is the total of all observed values, enabling a mean (in the mathematical sense, but also in the coolness sense) calculation via `sum / count`.
    """

    @type t() :: %__MODULE__{
            count: non_neg_integer(),
            sum: number(),
            values: [number()]
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:count, :sum, :values]
  end

  defmodule DimensionedHistogram do
    @moduledoc """
    A histogram with both a total aggregated value and an optional dimensional breakdown.

    - `:aggregate` is the `t:PrecomputedQuantiles.t/0` across all dimensions.
    - `:by` maps dimension values collected by the telemetry pipeline to their individual `t:PrecomputedQuantiles.t/0`.
    """

    @type t() :: %__MODULE__{
            aggregate: PrecomputedQuantiles.t(),
            by: %{String.t() => PrecomputedQuantiles.t()}
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:aggregate, :by]
  end

  defmodule DimensionedCounter do
    @moduledoc """
    A counter with both a total aggregated value and an optional dimensional breakdown.

    - `:aggregate` is the total count across all dimensions.
    - `:by` maps dimension values to their individual counts.
    """

    @type t() :: %__MODULE__{
            aggregate: non_neg_integer(),
            by: %{String.t() => non_neg_integer()}
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:aggregate, :by]
  end

  defmodule Bucket do
    @moduledoc """
    A single time bucket in the overall scenario's time series metrics.

    - `:offset_ms` is the millisecond offset from the start of the scenario's run.
    - `:active_users` is the number of concurrently running scenario users that were running within this bucket .
    - `:node_count` indicates how many nodes contributed data to this bucket. On the individual node breakdowns this will be `nil`.
    """

    @type t() :: %__MODULE__{
            offset_ms: non_neg_integer(),
            active_users: non_neg_integer(),
            node_count: pos_integer() | nil,
            histograms: %{String.t() => DimensionedHistogram.t()},
            counters: %{String.t() => DimensionedCounter.t()}
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:offset_ms, :active_users, :node_count, :histograms, :counters]
  end

  defmodule ScenarioResult do
    @moduledoc """
    A result for a scenario run, including summarized user results, aggregated counters, histograms, and bucketed time series data.
    """

    @type t() :: %__MODULE__{
            users: Users.t(),
            duration_ms: pos_integer(),
            histograms: %{String.t() => DimensionedHistogram.t()},
            counters: %{String.t() => DimensionedCounter.t()},
            time_series: [Bucket.t()]
          }

    LiveLoad.JSON.derive_encoder()
    defstruct [:users, :duration_ms, :histograms, :counters, :time_series]
  end

  defmodule NodeResult do
    @moduledoc """
    Per-node scenario results to allow drilling down to how scenarios behaved on specific nodes.

    When a node fails, the result takes the shape of `t:failed_result/0`.

    When a node succeeds, the result takes the shape of `t:successful_result/0`.
    """

    @type successful_result() :: %__MODULE__{
            node: node(),
            status: :ok,
            result: ScenarioResult.t()
          }

    @type failed_result() :: %__MODULE__{
            node: node(),
            status: :error,
            result: nil
          }

    @type t() :: successful_result() | failed_result()

    LiveLoad.JSON.derive_encoder()
    @enforce_keys [:node, :status]
    defstruct [:node, :status, :result]
  end

  @quantile_points Enum.map(0..100, &(&1 / 100))
  @quantile_points_count length(@quantile_points)

  @type t() :: %__MODULE__{
          name: String.t(),
          generated_at: DateTime.t(),
          liveload_version: String.t(),
          bucket_width_ms: pos_integer(),
          global: ScenarioResult.t(),
          nodes: [NodeResult.t()],
          quantile_points: [float()]
        }

  LiveLoad.JSON.derive_encoder()

  @enforce_keys [:name, :generated_at, :liveload_version, :bucket_width_ms, :global, :nodes, :quantile_points]
  defstruct [:name, :generated_at, :liveload_version, :bucket_width_ms, :global, :nodes, :quantile_points]

  @typedoc false
  @type result() :: Telemetry.Result.t() | :error

  @doc false
  @spec new(scenario :: Scenario.t(), node_results :: %{node() => result()}) :: t() | {:error, :no_results}
  def new(scenario, node_results) when map_size(node_results) > 0 do
    successful_results =
      node_results
      |> Map.values()
      |> Enum.filter(fn
        %Telemetry.Result{} -> true
        :error -> false
      end)

    merged_sketches =
      successful_results
      |> Enum.map(& &1.sketches)
      |> merge_cross_node_sketches()

    merged_counters =
      successful_results
      |> Enum.map(& &1.counters)
      |> merge_cross_node_counters()

    user_summary = %Users{
      total: sum_by(successful_results, & &1.total),
      succeeded: sum_by(successful_results, & &1.succeeded),
      failed: sum_by(successful_results, & &1.failed)
    }

    bucket_width_ms = List.first(successful_results).bucket_width_ms

    merged_time_series = merge_cross_node_time_series(node_results, bucket_width_ms)
    active_users_per_bucket = active_users_per_time_series_bucket(merged_time_series)
    max_bucket = merged_time_series |> Map.keys() |> Enum.max(fn -> 0 end)

    nodes =
      Enum.map(node_results, fn
        {node_name, :error} ->
          %NodeResult{
            node: to_string(node_name),
            status: :error
          }

        {node_name, %Telemetry.Result{} = result} ->
          node_active_users_per_bucket = active_users_per_time_series_bucket(result.time_series)
          node_max_bucket = result.time_series |> Map.keys() |> Enum.max(fn -> 0 end)

          %NodeResult{
            node: to_string(node_name),
            status: :ok,
            result: %ScenarioResult{
              users: %Users{total: result.total, succeeded: result.succeeded, failed: result.failed},
              duration_ms: (node_max_bucket + 1) * bucket_width_ms,
              histograms: precompute_histograms(result.sketches),
              counters: calculate_counters(result.counters),
              time_series: precompute_time_series(result.time_series, node_active_users_per_bucket, bucket_width_ms)
            }
          }
      end)

    %__MODULE__{
      name: inspect(scenario),
      generated_at: DateTime.utc_now(),
      liveload_version: liveload_version(),
      quantile_points: @quantile_points,
      bucket_width_ms: bucket_width_ms,
      global: %ScenarioResult{
        duration_ms: (max_bucket + 1) * bucket_width_ms,
        histograms: precompute_histograms(merged_sketches),
        counters: calculate_counters(merged_counters),
        users: user_summary,
        time_series: precompute_time_series(merged_time_series, active_users_per_bucket, bucket_width_ms)
      },
      nodes: nodes
    }
  end

  def new(_scenario, _node_results) do
    {:error, :no_results}
  end

  # These counters are specific to the active users calculation, we don't need to calculate them
  # and include them within all of the counters in the result.
  @internal_counters [:scenario_users_started, :scenario_users_completed]

  defp calculate_counters(counters) do
    {aggregates, dimensioned} = Enum.split_with(counters, fn {key, _} -> is_atom(key) end)
    precomputed_dimensioned_counters = build_dimension_pairs(dimensioned)

    aggregates
    |> Enum.reject(fn {name, _} -> name in @internal_counters end)
    |> Map.new(fn {name, count} ->
      {
        Atom.to_string(name),
        %DimensionedCounter{
          aggregate: count,
          by: Map.get(precomputed_dimensioned_counters, name, %{})
        }
      }
    end)
  end

  defp precompute_histograms(sketches) do
    {aggregates, dimensioned} = Enum.split_with(sketches, fn {key, _} -> is_atom(key) end)
    precomputed_quantiles_by_dimension = build_dimension_pairs(dimensioned, &precompute_quantiles/1)

    Map.new(aggregates, fn {name, sketch} ->
      {
        Atom.to_string(name),
        %DimensionedHistogram{
          aggregate: precompute_quantiles(sketch),
          by: Map.get(precomputed_quantiles_by_dimension, name, %{})
        }
      }
    end)
  end

  defp precompute_quantiles(sketch) do
    count = :ddskerl_std.total(sketch)

    if count == 0 do
      %PrecomputedQuantiles{
        count: 0,
        sum: 0,
        values: List.duplicate(0, @quantile_points_count)
      }
    else
      %PrecomputedQuantiles{
        count: count,
        sum: :ddskerl_std.sum(sketch),
        values: Enum.map(@quantile_points, &:ddskerl_std.quantile(sketch, &1))
      }
    end
  end

  defp precompute_time_series(merged_time_series, active_users, bucket_width_ms) do
    merged_time_series
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {bucket_idx, bucket_data} ->
      %Bucket{
        offset_ms: bucket_idx * bucket_width_ms,
        active_users: Map.get(active_users, bucket_idx, 0),
        node_count: Map.get(bucket_data, :node_count, nil),
        histograms: precompute_histograms(bucket_data.sketches),
        counters: calculate_counters(bucket_data.counters)
      }
    end)
  end

  defp build_dimension_pairs(dimensioned_metrics, fun \\ &Function.identity/1) do
    dimensioned_metrics
    |> Enum.group_by(
      fn {{name, _dimension}, _metric} -> name end,
      fn {{_name, dimension}, metric} -> {dimension, fun.(metric)} end
    )
    |> Map.new(fn {name, pairs} -> {name, Map.new(pairs)} end)
  end

  defp merge_cross_node_sketches(node_sketches) do
    node_sketches
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {name, sketches} ->
      {name, Enum.reduce(sketches, &:ddskerl_std.merge/2)}
    end)
  end

  defp merge_cross_node_counters(node_counters) do
    Enum.reduce(node_counters, %{}, fn counters, acc ->
      Map.merge(acc, counters, fn _k, v1, v2 -> v1 + v2 end)
    end)
  end

  defp merge_cross_node_time_series(node_results, bucket_width_ms) do
    global_epoch =
      node_results
      |> Enum.map(fn {_node, %Telemetry.Result{} = result} -> result.start_system_time end)
      |> Enum.min()

    node_results
    |> Enum.flat_map(fn {_node, %Telemetry.Result{} = result} ->
      offset = time_series_bucket_offset(result.start_system_time, global_epoch, bucket_width_ms)

      Enum.map(result.time_series, fn {bucket_idx, bucket_data} ->
        {bucket_idx + offset, bucket_data}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {idx, bucket_data} ->
      {idx, merge_cross_node_buckets(bucket_data)}
    end)
  end

  defp time_series_bucket_offset(node_system_time, global_epoch, bucket_width_ms) do
    offset_ms = System.convert_time_unit(node_system_time - global_epoch, :native, :millisecond)
    div(offset_ms, bucket_width_ms)
  end

  defp merge_cross_node_buckets(bucket_data) do
    %{
      sketches: merge_cross_node_sketches(Enum.map(bucket_data, & &1.sketches)),
      counters: merge_cross_node_counters(Enum.map(bucket_data, & &1.counters)),
      node_count: length(bucket_data)
    }
  end

  defp active_users_per_time_series_bucket(time_series) do
    sorted_buckets = time_series |> Map.keys() |> Enum.sort()

    {result, _acc_started, _acc_completed} =
      Enum.reduce(sorted_buckets, {%{}, 0, 0}, fn bucket_idx, {result, acc_started, acc_completed} ->
        bucket_data = Map.fetch!(time_series, bucket_idx)
        counters = bucket_data.counters

        started = Map.get(counters, :scenario_users_started, 0)
        completed = Map.get(counters, :scenario_users_completed, 0)

        new_started = acc_started + started
        new_completed = acc_completed + completed

        {Map.put(result, bucket_idx, new_started - new_completed), new_started, new_completed}
      end)

    result
  end

  defp liveload_version do
    :live_load
    |> Application.spec(:vsn)
    |> List.to_string()
  end

  # TODO: Remove when the minimum supported Elixir version is 1.18 which should be when 1.22 is released.
  @compile {:inline, sum_by: 2}
  if Version.match?(System.version(), ">= 1.18.0") do
    defp sum_by(enumerable, mapper), do: Enum.sum_by(enumerable, mapper)
  else
    defp sum_by(enumerable, mapper), do: enumerable |> Enum.map(mapper) |> Enum.sum()
  end
end
