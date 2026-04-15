defmodule LiveLoad.Cluster.AmocSeed do
  @moduledoc false

  @expected_record_tag :state
  @expected_field_count 8
  @connected_index 5
  @master_index 7

  # Force set the state of amoc's cluster on the runner nodes.
  # Amoc's cluster mechanism falls apart on large clusters, so we are forcefully
  # setting the state to the given record structure in order to avoid any gossiping and mesh.
  # This is a sort of "last straw" approach... the previous attempts of using pinging and connecting
  # the cluster through normal means failed as we approached larger and larger node pool sizes.
  # At more than 5 nodes, `:amoc_cluster.connect_nodes` caused a deadlock in `set_master_node`
  # during `:amoc_dist.do`. Instead, using `:amoc_cluster.ping` worked directly, but failed at
  # clusters of over 50 nodes. So here we are seeding directly into the state to force the necessary
  # state for a start based topology (and not a full mesh).
  def seed_amoc_cluster_on_node(cluster_nodes, master_peer) do
    self_node = node()
    connected = Enum.reject(cluster_nodes ++ [master_peer], &(&1 == self_node))

    :sys.replace_state(:amoc_cluster, fn state ->
      validate_state_shape!(state)

      state
      |> then(&:erlang.setelement(@connected_index, &1, connected))
      |> then(&:erlang.setelement(@master_index, &1, master_peer))
    end)

    :ok
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp validate_state_shape!(state) do
    actual_tag = elem(state, 0)
    actual_size = tuple_size(state)

    if actual_tag != @expected_record_tag or actual_size != @expected_field_count do
      throw({:unexpected_amoc_cluster_state_shape, %{tag: actual_tag, size: actual_size, state: state}})
    end
  end
end
