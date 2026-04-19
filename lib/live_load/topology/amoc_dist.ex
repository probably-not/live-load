defmodule LiveLoad.Topology.AmocDist do
  @moduledoc false
  # This is a hacked together parallel replacement for `:amoc_dist.do/3`
  # Currently, due to how amoc works during the distribution phase,
  # even after the hacks around priming nodes and directly injecting
  # the connections to the state, the whole initialization phase is very
  # slow. Some investigation has lead me to the fact that there are a few
  # sequential operations that loop over all nodes in the distributed amoc
  # flow. This module replaces these with parallel operations. In practice,
  # this must be upstreamed. For now, and for the purposes of getting LiveLoad
  # out there, this is a good enough solution.
  # Disclaimer: I am by no means an Erlang dev, so I had Claude Opus 4.6 help
  # me disect what `:amoc_dist.do` is actually doing and from there, I translated
  # it into this.

  @start_scenario_timeout to_timeout(minute: 5)
  @add_users_timeout to_timeout(minute: 5)

  def do_parallel(peer, scenario, total_users, settings) do
    with :ok <- setup_master_node(peer),
         :ok <- set_params(peer, scenario, settings),
         {:ok, runners} <- register_connection_action(peer),
         :ok <- setup_runners_parallel(peer, runners, scenario, settings),
         :ok <- add_users_parallel(peer, runners, total_users) do
      {:ok, :running}
    end
  end

  defp setup_master_node(peer) do
    case :rpc.call(peer, :amoc_cluster, :set_master_node, [peer]) do
      :ok ->
        case :rpc.call(peer, :amoc_controller, :disable, []) do
          :ok -> :ok
          error -> {:error, {:disable_failed, error}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp set_params(peer, scenario, settings) do
    :rpc.call(peer, :persistent_term, :put, [{:amoc_dist, :scenario}, scenario])
    :rpc.call(peer, :persistent_term, :put, [{:amoc_dist, :settings}, settings])
    :rpc.call(peer, :persistent_term, :put, [{:amoc_dist, :state}, :running])
    :rpc.call(peer, :persistent_term, :put, [{:amoc_dist, :last_id}, 0])
    :ok
  end

  defp register_connection_action(peer) do
    action = :rpc.call(peer, :erlang, :apply, [fn -> fn _node -> :ok end end, []])

    case :rpc.call(peer, :amoc_cluster, :on_new_connection, [action]) do
      {:ok, connected} -> {:ok, connected}
      {:error, _} = error -> error
    end
  end

  defp setup_runners_parallel(peer, runners, scenario, settings) do
    results =
      runners
      |> Task.async_stream(
        fn runner -> {runner, setup_single_runner(peer, runner, scenario, settings)} end,
        max_concurrency: length(runners),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    failures = for {node, result} <- results, result != :ok, into: %{}, do: {node, result}

    if map_size(failures) == 0 do
      :ok
    else
      {:error, {:setup_runners_failed, failures}}
    end
  end

  defp setup_single_runner(peer, runner, scenario, settings) do
    with :ok <- set_runner_master(runner, peer),
         :ok <- start_scenario(runner, scenario, settings) do
      :rpc.cast(peer, :gen_server, :cast, [:amoc_cluster, {:add_slave, runner}])
      :ok
    end
  end

  defp set_runner_master(runner, master_peer) do
    case :gen_server.call({:amoc_cluster, runner}, {:set_master_node, master_peer}, to_timeout(second: 30)) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  catch
    kind, reason -> {:error, {:set_master_node_failed, kind, reason}}
  end

  defp start_scenario(runner, scenario, settings) do
    :erpc.call(runner, :amoc_controller, :start_scenario, [scenario, settings], @start_scenario_timeout)
  catch
    kind, reason -> {:error, {:start_scenario_failed, kind, reason}}
  end

  defp add_users_parallel(peer, runners, total_users) when total_users > 0 do
    assignments = assign_users(runners, total_users)

    :rpc.call(peer, :persistent_term, :put, [{:amoc_dist, :last_id}, total_users])

    results =
      assignments
      |> Task.async_stream(
        fn {runner, start_id, end_id} ->
          result =
            :erpc.call(
              runner,
              :amoc_controller,
              :add_users,
              [start_id, end_id],
              @add_users_timeout
            )

          {runner, result}
        end,
        max_concurrency: length(assignments),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    failures = for {node, result} <- results, result != :ok, into: %{}, do: {node, result}

    if map_size(failures) == 0 do
      :ok
    else
      {:error, {:add_users_failed, failures}}
    end
  end

  defp add_users_parallel(_peer, _runners, 0), do: :ok

  defp assign_users(runners, total_users) do
    n = length(runners)
    per_node = div(total_users, n)
    remainder = rem(total_users, n)

    {assignments, _} =
      runners
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {runner, idx}, last_id ->
        count = per_node + if(idx < remainder, do: 1, else: 0)
        {{runner, last_id + 1, last_id + count}, last_id + count}
      end)

    assignments
  end
end
