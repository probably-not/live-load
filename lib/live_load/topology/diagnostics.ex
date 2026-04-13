defmodule LiveLoad.Topology.Diagnostics do
  @moduledoc false
  # `LiveLoad.Topology.Diagnostics` is a quick and dirty way of grabbing the diagnostics of processes
  # on the amoc peer and amoc runners so that when amoc has failures we can see what the direct issues
  # are without needing to introspect the nodes manually.

  def diagnose_runners(nodes) do
    liveness = run_liveness(nodes)
    probe = run_probe(nodes)

    Map.new(nodes, fn node ->
      {node,
       %{
         liveness: Map.fetch!(liveness, node),
         probe: Map.fetch!(probe, node)
       }}
    end)
  catch
    kind, reason ->
      %{probe_error: {:diagnose_runners_crashed, kind, reason}}
  end

  defp run_liveness(nodes) do
    nodes
    |> :erpc.multicall(Node, :self, [], 2000)
    |> then(&Enum.zip(nodes, &1))
    |> Map.new(fn {node, result} -> {node, format_liveness(result)} end)
  end

  defp run_probe(nodes) do
    nodes
    |> :erpc.multicall(__MODULE__, :probe_self, [], 30_000)
    |> then(&Enum.zip(nodes, &1))
    |> Map.new(fn {node, result} -> {node, format_probe(result)} end)
  end

  defp format_liveness({:ok, node}) when is_atom(node), do: :responsive
  defp format_liveness({:exit, {:erpc, :timeout}}), do: :timeout
  defp format_liveness({:exit, reason}), do: {:exit, reason}
  defp format_liveness({:error, reason}), do: {:error, reason}
  defp format_liveness({:throw, value}), do: {:throw, value}

  defp format_probe({:ok, snapshot}), do: snapshot
  defp format_probe({:error, reason}), do: %{probe_error: reason}
  defp format_probe({:exit, {:erpc, :timeout}}), do: %{probe_error: :erpc_timeout}
  defp format_probe({:exit, reason}), do: %{probe_error: {:probe_exit, reason}}
  defp format_probe({:throw, value}), do: %{probe_error: {:probe_throw, value}}

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
