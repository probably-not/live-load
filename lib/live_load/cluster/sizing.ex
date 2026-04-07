defmodule LiveLoad.Cluster.Sizing do
  @moduledoc false
  # `LiveLoad.Cluster.Sizing` is a heuristic sizing utility which determines
  # the maximum possible users per node based on a given `LiveLoad.Cluster.Node`
  # initialized by the FLAME pool.

  # Max 80% of the memory is allowed to be used on the machine.
  # Don't want the OOM killer coming at us for any reason.
  @memory_safety_factor 0.80

  # Reserved bytes for what the BEAM processes are going to take on Cluster Nodes.
  # 512 MB should cover everything we start up for amoc and the telemetry processes.
  @reserved_headroom_bytes 512 * 1024 * 1024

  # For each CPU code, the number of browser contexts we can create.
  # This is a pretty conservative number, but Playwright is a resource hog.
  @contexts_per_core 4

  def calculate_possible_users_per_node(%LiveLoad.Cluster.Node{} = node, browser_connection_adapter) do
    limited_by_node_memory =
      max_possible_by_memory_limits(
        node,
        browser_connection_adapter.browser_memory_usage_bytes(),
        browser_connection_adapter.context_memory_usage_bytes()
      )

    limited_by_node_cpu = max_possible_by_cpu_limits(node)

    min(limited_by_node_memory, limited_by_node_cpu)
  end

  defp max_possible_by_memory_limits(%LiveLoad.Cluster.Node{available_memory: available}, browser_bytes, context_bytes)
       when context_bytes > 0 do
    usable = trunc(available * @memory_safety_factor) - @reserved_headroom_bytes

    case usable - browser_bytes do
      remaining when remaining > 0 -> div(remaining, context_bytes)
      _ -> 0
    end
  end

  defp max_possible_by_cpu_limits(%LiveLoad.Cluster.Node{} = node) do
    cores =
      node.logical_processors_available ||
        node.logical_processors_online ||
        node.logical_processors ||
        node.schedulers_online

    cores * @contexts_per_core
  end
end
