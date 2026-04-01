# ** AI Tooling Disclaimer **
# I had Claude Opus 4.6 just generate these tests by giving it the `LiveLoad.Result` module and the `LiveLoad.Telemetry.Result` module
# and asking it to generate tests that validate my math and merging logic. It's really late here though, so I didn't validate any of these tests...
# I'm sort of trusting it blindly just, you know, for fun. I'm going to leave a TODO here to validate things later down the line.

# TODO: Make real tests or at least validate that Claude Opus 4.6 didn't cut corners just to get past testing like we've seen LLMs do in the past.

defmodule LiveLoad.ResultTest do
  use ExUnit.Case, async: true

  alias LiveLoad.Result
  alias LiveLoad.Result.Bucket
  alias LiveLoad.Result.DimensionedCounter
  alias LiveLoad.Result.DimensionedHistogram
  alias LiveLoad.Result.NodeResult
  alias LiveLoad.Result.PrecomputedQuantiles
  alias LiveLoad.Result.Users
  alias LiveLoad.Scenario.Example
  alias LiveLoad.Telemetry

  @error_rate 0.02
  @bucket_width_ms 5_000

  # ── Helpers ────────────────────────────────────────────────────────

  defp sketch(values) do
    Enum.reduce(values, :ddskerl_std.new(%{error: @error_rate}), &:ddskerl_std.insert(&2, &1))
  end

  defp telemetry_result(attrs) do
    defaults = %{
      total: 0,
      succeeded: 0,
      failed: 0,
      sketches: %{},
      counters: %{},
      bucket_width_ms: @bucket_width_ms,
      start_system_time: System.system_time(),
      time_series: %{}
    }

    struct!(Telemetry.Result, Map.merge(defaults, Map.new(attrs)))
  end

  # ── Metadata ───────────────────────────────────────────────────────

  describe "metadata" do
    test "name is the inspected scenario module" do
      result = Result.new(Example, %{node1: telemetry_result(total: 1, succeeded: 1)})

      assert result.name == "LiveLoad.Scenario.Example"
    end

    test "generated_at is a recent DateTime" do
      before = DateTime.utc_now()
      result = Result.new(Example, %{node1: telemetry_result(total: 1, succeeded: 1)})
      after_ = DateTime.utc_now()

      assert DateTime.compare(result.generated_at, before) in [:eq, :gt]
      assert DateTime.compare(result.generated_at, after_) in [:eq, :lt]
    end

    test "liveload_version is a string" do
      result = Result.new(Example, %{node1: telemetry_result(total: 1, succeeded: 1)})

      assert is_binary(result.liveload_version)
    end

    test "quantile_points is 101 floats from 0.0 to 1.0" do
      result = Result.new(Example, %{node1: telemetry_result(total: 1, succeeded: 1)})

      assert length(result.quantile_points) == 101
      assert hd(result.quantile_points) == 0.0
      assert List.last(result.quantile_points) == 1.0
    end

    test "bucket_width_ms matches the telemetry results" do
      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, bucket_width_ms: 10_000)
        })

      assert result.bucket_width_ms == 10_000
    end

    test "returns {:error, :no_results} for empty node results" do
      assert Result.new(Example, %{}) == {:error, :no_results}
    end
  end

  # ── Users ──────────────────────────────────────────────────────────

  describe "users aggregation" do
    test "single node" do
      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 100, succeeded: 95, failed: 5)
        })

      assert result.global.users == %Users{total: 100, succeeded: 95, failed: 5}
    end

    test "multiple nodes sum correctly" do
      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 100, succeeded: 90, failed: 10),
          node2: telemetry_result(total: 50, succeeded: 48, failed: 2)
        })

      assert result.global.users == %Users{total: 150, succeeded: 138, failed: 12}
    end

    test "per-node users are preserved individually" do
      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 100, succeeded: 90, failed: 10),
          node2: telemetry_result(total: 50, succeeded: 48, failed: 2)
        })

      users_by_node =
        Map.new(result.nodes, fn %NodeResult{node: n, result: r} -> {n, r.users} end)

      assert users_by_node["node1"] == %Users{total: 100, succeeded: 90, failed: 10}
      assert users_by_node["node2"] == %Users{total: 50, succeeded: 48, failed: 2}
    end
  end

  # ── Histogram Materialization ──────────────────────────────────────

  describe "histogram materialization" do
    test "sketch with known values produces correct quantiles" do
      # Insert 100 values: 1, 2, 3, ..., 100
      values = Enum.to_list(1..100)
      s = sketch(values)

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 100,
              succeeded: 100,
              sketches: %{scenario_duration_us: s}
            )
        })

      histogram = result.global.histograms["scenario_duration_us"]
      assert %DimensionedHistogram{} = histogram
      assert %PrecomputedQuantiles{} = histogram.aggregate

      # Count matches
      assert histogram.aggregate.count == 100

      # Sum matches
      assert histogram.aggregate.sum == Enum.sum(values)

      # Values array has 101 elements
      assert length(histogram.aggregate.values) == 101

      # Median (index 50) should be close to 50
      assert_in_delta Enum.at(histogram.aggregate.values, 50), 50, 2

      # Maximum (index 100) should be close to 100
      assert_in_delta List.last(histogram.aggregate.values), 100, 2

      # p99 (index 99) should be close to 99
      assert_in_delta Enum.at(histogram.aggregate.values, 99), 99, 2
    end

    test "single-value sketch has all quantiles equal to that value" do
      s = sketch([42_000])

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 1,
              succeeded: 1,
              sketches: %{scenario_duration_us: s}
            )
        })

      histogram = result.global.histograms["scenario_duration_us"]
      assert histogram.aggregate.count == 1

      # All quantiles of a single-value sketch should return that value (within DDSketch error)
      Enum.each(histogram.aggregate.values, fn v ->
        assert_in_delta v, 42_000, 42_000 * @error_rate * 2
      end)
    end

    test "dimensional breakdown produces aggregate and by fields" do
      flat_sketch = sketch([100, 200, 300])
      dim_a = sketch([100])
      dim_b = sketch([200, 300])

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 3,
              succeeded: 3,
              sketches: %{
                :http_request_duration_us => flat_sketch,
                {:http_request_duration_us, "document"} => dim_a,
                {:http_request_duration_us, "fetch"} => dim_b
              }
            )
        })

      histogram = result.global.histograms["http_request_duration_us"]

      # Aggregate matches the flat sketch
      assert histogram.aggregate.count == 3

      # Dimensional breakdown has correct keys
      assert Map.has_key?(histogram.by, "document")
      assert Map.has_key?(histogram.by, "fetch")
      assert map_size(histogram.by) == 2

      # Dimensional counts are correct
      assert histogram.by["document"].count == 1
      assert histogram.by["fetch"].count == 2
    end

    test "sketch with no dimensional data has empty by map" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 1,
              succeeded: 1,
              sketches: %{scenario_duration_us: sketch([100])}
            )
        })

      histogram = result.global.histograms["scenario_duration_us"]
      assert histogram.by == %{}
    end

    test "histogram keys are stringified atom names" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 1,
              succeeded: 1,
              sketches: %{
                http_request_duration_us: sketch([100]),
                http_request_ttfb_us: sketch([50])
              }
            )
        })

      assert Map.has_key?(result.global.histograms, "http_request_duration_us")
      assert Map.has_key?(result.global.histograms, "http_request_ttfb_us")
      refute Map.has_key?(result.global.histograms, :http_request_duration_us)
    end
  end

  # ── Counter Materialization ────────────────────────────────────────

  describe "counter materialization" do
    test "aggregated counter with dimensional breakdown" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              counters: %{
                :liveview_navigations => 25,
                {:liveview_navigations, "patch"} => 18,
                {:liveview_navigations, "redirect"} => 7
              }
            )
        })

      counter = result.global.counters["liveview_navigations"]
      assert %DimensionedCounter{} = counter
      assert counter.aggregate == 25
      assert counter.by == %{"patch" => 18, "redirect" => 7}
    end

    test "counter keys are stringified atom names" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 1,
              succeeded: 1,
              counters: %{liveview_navigations: 5}
            )
        })

      assert Map.has_key?(result.global.counters, "liveview_navigations")
    end

    test "internal counters are filtered from output" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              counters: %{
                scenario_users_started: 10,
                scenario_users_completed: 10,
                liveview_navigations: 5
              }
            )
        })

      refute Map.has_key?(result.global.counters, "scenario_users_started")
      refute Map.has_key?(result.global.counters, "scenario_users_completed")
      assert Map.has_key?(result.global.counters, "liveview_navigations")
    end

    test "counter with no dimensional data has empty by map" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 1,
              succeeded: 1,
              counters: %{liveview_navigations: 5}
            )
        })

      assert result.global.counters["liveview_navigations"].by == %{}
    end
  end

  # ── Cross-Node Merge ───────────────────────────────────────────────

  describe "cross-node sketch merge" do
    test "sketches from two nodes are merged correctly" do
      # Node 1: values 1-50, Node 2: values 51-100
      # Merged should behave like a single sketch with values 1-100
      node1_sketch = sketch(Enum.to_list(1..50))
      node2_sketch = sketch(Enum.to_list(51..100))

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 50,
              succeeded: 50,
              sketches: %{scenario_duration_us: node1_sketch}
            ),
          node2:
            telemetry_result(
              total: 50,
              succeeded: 50,
              sketches: %{scenario_duration_us: node2_sketch}
            )
        })

      merged = result.global.histograms["scenario_duration_us"].aggregate

      assert merged.count == 100
      assert merged.sum == Enum.sum(1..100)

      # Median of 1-100 should be around 50
      assert_in_delta Enum.at(merged.values, 50), 50, 3

      # Max should be around 100
      assert_in_delta List.last(merged.values), 100, 2
    end

    test "dimensional sketches merge across nodes" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              sketches: %{
                :http_request_duration_us => sketch([100, 200]),
                {:http_request_duration_us, "document"} => sketch([100]),
                {:http_request_duration_us, "fetch"} => sketch([200])
              }
            ),
          node2:
            telemetry_result(
              total: 10,
              succeeded: 10,
              sketches: %{
                :http_request_duration_us => sketch([300, 400]),
                {:http_request_duration_us, "document"} => sketch([300]),
                {:http_request_duration_us, "fetch"} => sketch([400])
              }
            )
        })

      histogram = result.global.histograms["http_request_duration_us"]

      # Aggregate merged: 4 values total
      assert histogram.aggregate.count == 4

      # Dimensional merged: 2 each
      assert histogram.by["document"].count == 2
      assert histogram.by["fetch"].count == 2
    end

    test "sketch present on only one node still appears in merged result" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              sketches: %{
                :http_request_duration_us => sketch([100]),
                {:http_request_duration_us, "document"} => sketch([100])
              }
            ),
          node2:
            telemetry_result(
              total: 10,
              succeeded: 10,
              sketches: %{
                :http_request_duration_us => sketch([200]),
                {:http_request_duration_us, "fetch"} => sketch([200])
              }
            )
        })

      histogram = result.global.histograms["http_request_duration_us"]

      # Both dimensions present even though each came from only one node
      assert histogram.by["document"].count == 1
      assert histogram.by["fetch"].count == 1
    end
  end

  describe "cross-node counter merge" do
    test "counters from two nodes sum correctly" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 50,
              succeeded: 50,
              counters: %{
                :liveview_navigations => 100,
                {:liveview_navigations, "patch"} => 80,
                {:liveview_navigations, "redirect"} => 20
              }
            ),
          node2:
            telemetry_result(
              total: 50,
              succeeded: 50,
              counters: %{
                :liveview_navigations => 75,
                {:liveview_navigations, "patch"} => 50,
                {:liveview_navigations, "redirect"} => 25
              }
            )
        })

      counter = result.global.counters["liveview_navigations"]
      assert counter.aggregate == 175
      assert counter.by["patch"] == 130
      assert counter.by["redirect"] == 45
    end
  end

  # ── Active Users ───────────────────────────────────────────────────

  describe "active users computation" do
    test "cumulative start minus complete gives active users per bucket" do
      # Bucket 0: 10 start, 0 complete → 10 active
      # Bucket 1: 5 start, 3 complete → 12 active
      # Bucket 2: 0 start, 7 complete → 5 active
      # Bucket 3: 0 start, 5 complete → 0 active
      time_series = %{
        0 => %{
          sketches: %{},
          counters: %{scenario_users_started: 10, scenario_users_completed: 0}
        },
        1 => %{
          sketches: %{},
          counters: %{scenario_users_started: 5, scenario_users_completed: 3}
        },
        2 => %{
          sketches: %{},
          counters: %{scenario_users_started: 0, scenario_users_completed: 7}
        },
        3 => %{
          sketches: %{},
          counters: %{scenario_users_started: 0, scenario_users_completed: 5}
        }
      }

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 15,
              succeeded: 15,
              time_series: time_series,
              counters: %{scenario_users_started: 15, scenario_users_completed: 15}
            )
        })

      active_users = Enum.map(result.global.time_series, & &1.active_users)
      assert active_users == [10, 12, 5, 0]
    end

    test "active users work on per-node results too" do
      time_series = %{
        0 => %{
          sketches: %{},
          counters: %{scenario_users_started: 5, scenario_users_completed: 0}
        },
        1 => %{
          sketches: %{},
          counters: %{scenario_users_started: 0, scenario_users_completed: 5}
        }
      }

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 5,
              succeeded: 5,
              time_series: time_series,
              counters: %{scenario_users_started: 5, scenario_users_completed: 5}
            )
        })

      node_result = hd(result.nodes)
      node_active = Enum.map(node_result.result.time_series, & &1.active_users)
      assert node_active == [5, 0]
    end
  end

  # ── Time Series ────────────────────────────────────────────────────

  describe "time series" do
    test "buckets are sorted by offset_ms" do
      time_series = %{
        2 => %{sketches: %{}, counters: %{}},
        0 => %{sketches: %{}, counters: %{}},
        1 => %{sketches: %{}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, time_series: time_series)
        })

      offsets = Enum.map(result.global.time_series, & &1.offset_ms)
      assert offsets == [0, 5_000, 10_000]
    end

    test "offset_ms equals bucket_index * bucket_width_ms" do
      time_series = %{
        0 => %{sketches: %{}, counters: %{}},
        3 => %{sketches: %{}, counters: %{}},
        7 => %{sketches: %{}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, time_series: time_series, bucket_width_ms: 2_000)
        })

      offsets = Enum.map(result.global.time_series, & &1.offset_ms)
      assert offsets == [0, 6_000, 14_000]
    end

    test "per-bucket histograms and counters are materialized" do
      time_series = %{
        0 => %{
          sketches: %{
            :http_request_duration_us => sketch([100, 200]),
            {:http_request_duration_us, "document"} => sketch([100])
          },
          counters: %{
            :liveview_navigations => 5,
            {:liveview_navigations, "patch"} => 3,
            {:liveview_navigations, "redirect"} => 2
          }
        }
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 2, succeeded: 2, time_series: time_series)
        })

      bucket = hd(result.global.time_series)
      assert %Bucket{} = bucket

      # Histogram materialized in bucket
      assert bucket.histograms["http_request_duration_us"].aggregate.count == 2
      assert bucket.histograms["http_request_duration_us"].by["document"].count == 1

      # Counter materialized in bucket
      assert bucket.counters["liveview_navigations"].aggregate == 5
      assert bucket.counters["liveview_navigations"].by["patch"] == 3
    end

    test "duration_ms derived from max bucket index" do
      time_series = %{
        0 => %{sketches: %{}, counters: %{}},
        1 => %{sketches: %{}, counters: %{}},
        5 => %{sketches: %{}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, time_series: time_series)
        })

      # max bucket is 5, so duration = (5 + 1) * 5000 = 30000
      assert result.global.duration_ms == 30_000
    end

    test "node_count is nil for per-node time series" do
      time_series = %{
        0 => %{sketches: %{}, counters: %{}},
        1 => %{sketches: %{}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, time_series: time_series)
        })

      node_result = hd(result.nodes)

      Enum.each(node_result.result.time_series, fn bucket ->
        assert bucket.node_count == nil
      end)
    end
  end

  # ── Cross-Node Time Series Merge ───────────────────────────────────

  describe "cross-node time series merge" do
    test "buckets from same-start nodes align without offset" do
      sys_time = System.system_time()

      ts1 = %{
        0 => %{sketches: %{scenario_duration_us: sketch([100])}, counters: %{}},
        1 => %{sketches: %{scenario_duration_us: sketch([200])}, counters: %{}}
      }

      ts2 = %{
        0 => %{sketches: %{scenario_duration_us: sketch([300])}, counters: %{}},
        1 => %{sketches: %{scenario_duration_us: sketch([400])}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 2, succeeded: 2, time_series: ts1, start_system_time: sys_time),
          node2: telemetry_result(total: 2, succeeded: 2, time_series: ts2, start_system_time: sys_time)
        })

      # Both nodes contributed to both buckets
      assert length(result.global.time_series) == 2

      Enum.each(result.global.time_series, fn bucket ->
        assert bucket.node_count == 2
      end)

      # Merged sketch counts: 1 from each node per bucket = 2 per bucket
      [b0, b1] = result.global.time_series
      assert b0.histograms["scenario_duration_us"].aggregate.count == 2
      assert b1.histograms["scenario_duration_us"].aggregate.count == 2
    end

    test "late-starting node buckets are offset correctly" do
      # node1 starts at time 0, node2 starts 1 bucket later (5000ms)
      sys_time_node1 = System.system_time()
      # Offset by exactly one bucket width in native units
      offset_native = System.convert_time_unit(@bucket_width_ms, :millisecond, :native)
      sys_time_node2 = sys_time_node1 + offset_native

      ts1 = %{
        0 => %{sketches: %{scenario_duration_us: sketch([100])}, counters: %{}},
        1 => %{sketches: %{scenario_duration_us: sketch([200])}, counters: %{}}
      }

      ts2 = %{
        0 => %{sketches: %{scenario_duration_us: sketch([300])}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 2, succeeded: 2, time_series: ts1, start_system_time: sys_time_node1),
          node2: telemetry_result(total: 1, succeeded: 1, time_series: ts2, start_system_time: sys_time_node2)
        })

      # Global timeline: bucket 0 (node1 only), bucket 1 (both nodes), no bucket 2 from node2
      # node1 has buckets 0,1. node2's bucket 0 shifts to global bucket 1.
      buckets = result.global.time_series
      bucket_map = Map.new(buckets, &{&1.offset_ms, &1})

      # Bucket at offset 0: only node1
      assert bucket_map[0].node_count == 1
      assert bucket_map[0].histograms["scenario_duration_us"].aggregate.count == 1

      # Bucket at offset 5000: node1's bucket 1 + node2's bucket 0
      assert bucket_map[5_000].node_count == 2
      assert bucket_map[5_000].histograms["scenario_duration_us"].aggregate.count == 2
    end

    test "merged active users sums across nodes" do
      sys_time = System.system_time()

      ts1 = %{
        0 => %{sketches: %{}, counters: %{scenario_users_started: 10, scenario_users_completed: 0}},
        1 => %{sketches: %{}, counters: %{scenario_users_started: 0, scenario_users_completed: 10}}
      }

      ts2 = %{
        0 => %{sketches: %{}, counters: %{scenario_users_started: 5, scenario_users_completed: 0}},
        1 => %{sketches: %{}, counters: %{scenario_users_started: 0, scenario_users_completed: 5}}
      }

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              time_series: ts1,
              start_system_time: sys_time,
              counters: %{scenario_users_started: 10, scenario_users_completed: 10}
            ),
          node2:
            telemetry_result(
              total: 5,
              succeeded: 5,
              time_series: ts2,
              start_system_time: sys_time,
              counters: %{scenario_users_started: 5, scenario_users_completed: 5}
            )
        })

      active = Enum.map(result.global.time_series, & &1.active_users)

      # Bucket 0: 15 started, 0 completed → 15 active
      # Bucket 1: 0 started, 15 completed → 0 active
      assert active == [15, 0]
    end
  end

  # ── Node Results ───────────────────────────────────────────────────

  describe "node results" do
    test "each node gets its own materialized result" do
      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 10,
              succeeded: 10,
              sketches: %{scenario_duration_us: sketch(Enum.to_list(1..10))},
              counters: %{liveview_navigations: 20}
            ),
          node2:
            telemetry_result(
              total: 5,
              succeeded: 5,
              sketches: %{scenario_duration_us: sketch(Enum.to_list(100..104))},
              counters: %{liveview_navigations: 8}
            )
        })

      assert length(result.nodes) == 2

      nodes_by_name = Map.new(result.nodes, &{&1.node, &1.result})

      # Node 1 has its own counts
      assert nodes_by_name["node1"].histograms["scenario_duration_us"].aggregate.count == 10
      assert nodes_by_name["node1"].counters["liveview_navigations"].aggregate == 20

      # Node 2 has its own counts
      assert nodes_by_name["node2"].histograms["scenario_duration_us"].aggregate.count == 5
      assert nodes_by_name["node2"].counters["liveview_navigations"].aggregate == 8
    end

    test "node names are stringified" do
      result =
        Result.new(Example, %{
          :runner@host1 => telemetry_result(total: 1, succeeded: 1)
        })

      assert hd(result.nodes).node == "runner@host1"
    end

    test "per-node duration_ms is computed from that node's max bucket" do
      ts1 = %{
        0 => %{sketches: %{}, counters: %{}},
        9 => %{sketches: %{}, counters: %{}}
      }

      ts2 = %{
        0 => %{sketches: %{}, counters: %{}},
        3 => %{sketches: %{}, counters: %{}}
      }

      result =
        Result.new(Example, %{
          node1: telemetry_result(total: 1, succeeded: 1, time_series: ts1),
          node2: telemetry_result(total: 1, succeeded: 1, time_series: ts2)
        })

      nodes_by_name = Map.new(result.nodes, &{&1.node, &1.result})

      # Node 1: max bucket 9, so (9+1) * 5000 = 50000
      assert nodes_by_name["node1"].duration_ms == 50_000

      # Node 2: max bucket 3, so (3+1) * 5000 = 20000
      assert nodes_by_name["node2"].duration_ms == 20_000
    end
  end

  # ── JSON Serialization ─────────────────────────────────────────────

  describe "JSON serialization" do
    test "full result is JSON-encodable" do
      time_series = %{
        0 => %{
          sketches: %{
            :http_request_duration_us => sketch([100, 200, 300]),
            {:http_request_duration_us, "document"} => sketch([100])
          },
          counters: %{
            :liveview_navigations => 5,
            {:liveview_navigations, "patch"} => 3,
            scenario_users_started: 3,
            scenario_users_completed: 0
          }
        },
        1 => %{
          sketches: %{http_request_duration_us: sketch([400, 500])},
          counters: %{
            liveview_navigations: 2,
            scenario_users_started: 0,
            scenario_users_completed: 3
          }
        }
      }

      result =
        Result.new(Example, %{
          node1:
            telemetry_result(
              total: 3,
              succeeded: 3,
              sketches: %{
                :http_request_duration_us => sketch([100, 200, 300, 400, 500]),
                {:http_request_duration_us, "document"} => sketch([100])
              },
              counters: %{
                :liveview_navigations => 7,
                {:liveview_navigations, "patch"} => 3,
                scenario_users_started: 3,
                scenario_users_completed: 3
              },
              time_series: time_series
            )
        })

      assert json = LiveLoad.JSON.encode!(result)
      assert is_binary(json)

      # Round-trip: decode and verify structure
      {:ok, decoded} = LiveLoad.JSON.decode(json)

      assert decoded["name"] == "LiveLoad.Scenario.Example"
      assert is_binary(decoded["generated_at"])
      assert is_binary(decoded["liveload_version"])
      assert is_list(decoded["quantile_points"])
      assert length(decoded["quantile_points"]) == 101

      # Global result present
      assert decoded["global"]["users"]["total"] == 3
      assert is_list(decoded["global"]["time_series"])
      assert length(decoded["global"]["time_series"]) == 2

      # Histograms structure
      histogram = decoded["global"]["histograms"]["http_request_duration_us"]
      assert is_map(histogram["aggregate"])
      assert length(histogram["aggregate"]["values"]) == 101
      assert is_map(histogram["by"])

      # Counters structure — internal counters filtered
      refute Map.has_key?(decoded["global"]["counters"], "scenario_users_started")
      assert decoded["global"]["counters"]["liveview_navigations"]["aggregate"] == 7

      # Nodes present
      assert length(decoded["nodes"]) == 1
    end
  end
end
