defmodule LiveLoad.Scenario.Throttle.Ramp do
  @moduledoc """
  `LiveLoad.Scenario.Throttle.Ramp` defines the options for creating a gradual ramp up on a throttle.
  """

  @typedoc """
  The target to ramp up on the throttle.
  """
  @type target() :: pos_integer()

  @typedoc """
  The duration for a ramp up to last.

  This option is mutually exclusive with `t:steps_opt/0` and `t:interval_opt/0`, which define a step based ramp up.
  """
  @type duration_opt() :: {:duration, pos_integer()}

  @typedoc """
  The number of steps to take while ramping up.

  This option requires the `t:interval_opt/0` option to be set as well.

  This option is mutually exclusive with `t:duration_opt/0`, which defines a duration based ramp up.
  """
  @type steps_opt() :: {:steps, pos_integer()}

  @typedoc """
  The interval between steps of steps to take while ramping up.

  This option requires the `t:steps_opt/0` option to be set as well.

  This option is mutually exclusive with `t:duration_opt/0`, which defines a duration based ramp up.
  """
  @type interval_opt() :: {:interval, pos_integer()}

  @typedoc """
  Options for creating a ramp.
  """
  @type option() :: duration_opt() | steps_opt() | interval_opt()

  @typedoc false
  @type t() :: %__MODULE__{
          target: non_neg_integer(),
          duration: pos_integer() | nil,
          steps: pos_integer() | nil,
          interval: pos_integer() | nil
        }

  @enforce_keys [:target]
  defstruct [:target, :duration, :steps, :interval]

  @doc false
  def build(opts) when is_list(opts) do
    case target(opts) do
      {:ok, target} -> plan(target, opts)
      {:error, _reason} = error -> error
    end
  end

  def build(opts), do: {:error, {:invalid_options_passed_to_ramp, opts}}

  defp target(opts) do
    case Keyword.fetch(opts, :target) do
      {:ok, target} when is_integer(target) and target >= 0 -> {:ok, target}
      :error -> {:error, {:missing_target_for_ramp, opts}}
    end
  end

  defp plan(target, opts) do
    cond do
      Keyword.has_key?(opts, :duration) ->
        duration_ramp(target, opts[:duration])

      Keyword.has_key?(opts, :steps) and Keyword.has_key?(opts, :interval) ->
        step_ramp(target, opts[:steps], opts[:interval])

      true ->
        {:error, {:invalid_options_passed_to_ramp, opts}}
    end
  end

  defp duration_ramp(target, duration) when is_integer(duration) and duration > 0 do
    %__MODULE__{target: target, duration: duration}
  end

  defp step_ramp(target, steps, interval)
       when is_integer(steps) and steps > 0 and is_integer(interval) and interval > 0 do
    %__MODULE__{target: target, steps: steps, interval: interval}
  end

  @doc false
  def to_amoc_gradual_plan(%__MODULE__{duration: duration}) when is_integer(duration) do
    %{duration: duration}
  end

  @doc false
  def to_amoc_gradual_plan(%__MODULE__{steps: steps, interval: interval})
      when is_integer(steps) and is_integer(interval) do
    %{step_count: steps, step_interval: interval}
  end
end
