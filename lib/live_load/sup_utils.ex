defmodule LiveLoad.SupUtils do
  @moduledoc false
  # A shared utility for a pattern that I've been using in many of my supervisors.

  def find_child(supervisor, child_id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find(fn
      {^child_id, pid, _type, _modules} when is_pid(pid) -> true
      _ -> false
    end)
    |> then(fn
      {^child_id, pid, _type, _modules} when is_pid(pid) -> pid
      _other -> nil
    end)
  end
end
