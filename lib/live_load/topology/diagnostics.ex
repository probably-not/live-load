defmodule LiveLoad.Topology.Diagnostics do
  @moduledoc false
  # `LiveLoad.Topology.Diagnostics` is a quick and dirty way of grabbing the diagnostics of processes
  # on the amoc peer and amoc runners so that when amoc has failures we can see what the direct issues
  # are without needing to introspect the nodes manually.

  @process_info_keys [
    :message_queue_len,
    :current_function,
    :current_stacktrace,
    :status,
    :reductions,
    :memory
  ]

  def probe_self do
    %{
      node: node(),
      wall_clock: System.system_time(:millisecond),
      amoc_cluster: probe_amoc_cluster(),
      amoc_cluster_status: safe(fn -> :amoc_cluster.get_status() end),
      connected_nodes: Node.list(),
      uptime_ms: elem(:erlang.statistics(:wall_clock), 0),
      run_queue: :erlang.statistics(:run_queue),
      memory: Map.new(:erlang.memory())
    }
  end

  defp probe_amoc_cluster do
    case Process.whereis(:amoc_cluster) do
      nil -> %{registered: false}
      pid when is_pid(pid) -> %{registered: true, pid: pid, info: Process.info(pid, @process_info_keys)}
    end
  end

  defp safe(fun) do
    {:ok, fun.()}
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
