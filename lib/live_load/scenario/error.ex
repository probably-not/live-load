defmodule LiveLoad.Scenario.Error do
  @moduledoc """
  Any error that occurs within a `LiveLoad.Scenario` is marked on the `LiveLoad.Scenario.Context`
  as a `#{inspect(__MODULE__)}`.
  """
  @enforce_keys [:step, :op, :args, :reason]
  defexception [:step, :op, :args, :reason]

  @type t() :: %__MODULE__{}

  @doc false
  @impl true
  def message(%__MODULE__{} = error) do
    args_str = Enum.map_join(error.args, ", ", &inspect/1)
    "Step #{error.step}: #{error.op}(#{args_str}) failed - #{inspect(error.reason)}"
  end
end
