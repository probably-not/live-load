defmodule LiveLoad.Cluster.AmocSeed do
  @moduledoc false

  def seed_amoc_cluster_on_node(cluster_nodes) do
    cluster_nodes
    |> Task.async_stream(
      fn
        cluster_node when cluster_node == node() -> {cluster_node, :pong}
        cluster_node -> {cluster_node, ping_with_retries(cluster_node, 5)}
      end,
      timeout: to_timeout(minute: 1),
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, {node, :pong}} -> {node, :pong}
      {:ok, {node, :pang}} -> {node, :pang}
      {:ok, {node, {:error, reason}}} -> {node, {:error, reason}}
      {:exit, reason} -> {:error, {:seed_task_exit, reason}}
    end)
  end

  defp ping_with_retries(peer, attempts_left, errors \\ [])

  defp ping_with_retries(_peer, 0, errors) do
    {:error, {:retries_exhausted, Enum.reverse(errors)}}
  end

  defp ping_with_retries(peer, attempts_left, errors) do
    :amoc_cluster.ping(peer)
  catch
    kind, reason -> ping_with_retries(peer, attempts_left - 1, [{kind, reason} | errors])
  else
    :pang -> ping_with_retries(peer, attempts_left - 1, [:pang | errors])
    :pong -> :pong
  end
end
