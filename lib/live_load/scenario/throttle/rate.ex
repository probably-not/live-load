defmodule LiveLoad.Scenario.Throttle.Rate do
  @moduledoc """
  `LiveLoad.Scenario.Throttle.Rate` provides a basic rate limiter which limits to a specific number of events per interval configured.

  This is the most commonly used throttle type. It works cluster wide across the entire distributed load test and ensures that the concurrent
  executions do not pass the configured rate limit. This rate limiting is smoothed and ensures that no bursts occur at the beginning of an interval.

  ## Examples

  ```elixir
  # 100 per minute (the default interval)
  #{__MODULE__}.new(:my_throttle, 100)

  # 10 per second
  #{__MODULE__}.new(:my_throttle, 10) |> #{__MODULE__}.interval(to_timeout(second: 1))

  # 500 per 30 seconds
  #{__MODULE__}.new(:my_throttle, 500) |> #{__MODULE__}.interval(to_timeout(second: 30))

  # Start at 10 per minute and ramp up to 100 per minute over the next 5 minutes
  #{__MODULE__}.new(:my_throttle, 10) |> #{__MODULE__}.ramp(100, duration: to_timeout(minute: 5))
  ```
  """

  alias __MODULE__
  alias LiveLoad.Scenario.Throttle.Ramp

  @typedoc """
  The rate to which to throttle events.
  """
  @type rate() :: pos_integer()

  @opaque t() :: %__MODULE__{
            name: atom(),
            rate: rate(),
            interval: pos_integer(),
            ramp_opts: [Ramp.option()] | nil,
            ramp: Ramp.t() | nil
          }

  @enforce_keys [:name, :rate]
  defstruct [:name, :rate, :ramp_opts, :ramp, interval: to_timeout(minute: 1)]

  @doc """
  Creates a new `LiveLoad.Scenario.Throttle.Rate` with the given name and rate.

  By default, the rate will be calculated over a one minute interval. To set it
  to different a different interval, use `interval/2` to set a new one.
  """
  @spec new(name :: atom(), rate :: rate()) :: t()
  def new(name, rate) when is_atom(name) and not is_nil(name) and is_integer(rate) and rate > 0 do
    %__MODULE__{name: name, rate: rate}
  end

  @doc """
  Sets the rate interval in milliseconds.

  Must be a positive integer. The default is one minute.
  """
  @spec interval(rate :: t(), interval :: non_neg_integer()) :: t()
  def interval(%__MODULE__{} = rate, interval) when is_integer(interval) and interval > 0 do
    %{rate | interval: interval}
  end

  @doc """
  Attaches a gradually ramping rate change to the throttle.

  ## Options

    * `:duration`: The duration of the gradual ramp up in milliseconds
    * `:steps`: The number of steps to take while ramping up. Requires an `:interval` value.
    * `:interval`: The interval at which to take each step. Requires a `:step` value.
  """
  @spec ramp(rate :: t(), target :: Ramp.target(), ramp_opts :: [Ramp.option()]) :: t()
  def ramp(%__MODULE__{} = rate, target, opts) when is_list(opts) do
    %{rate | ramp_opts: [{:target, target} | opts]}
  end

  defimpl LiveLoad.Scenario.Throttle do
    def name(%Rate{name: name}), do: name

    def validate(%Rate{name: nil} = throttle) do
      {:error, {:missing_name, throttle}}
    end

    def validate(%Rate{name: name, rate: rate}) when not (is_integer(rate) and rate > 0) do
      {:error, {:invalid_rate, name, rate}}
    end

    def validate(%Rate{name: name, interval: interval}) when not (is_integer(interval) and interval > 0) do
      {:error, {:invalid_interval, name, interval}}
    end

    def validate(%Rate{ramp_opts: nil} = throttle), do: {:ok, throttle}

    def validate(%Rate{ramp_opts: opts} = rate) do
      case Ramp.build(opts) do
        %Ramp{} = ramp ->
          {:ok, %{rate | ramp: ramp}}

        {:error, reason} ->
          {:error, {:invalid_ramp_opts, reason}}
      end
    end

    def to_amoc_config(%Rate{} = rate) do
      %{rate: rate.rate, interval: rate.interval}
    end

    def to_amoc_gradual_plan(%Rate{ramp: nil}), do: nil

    def to_amoc_gradual_plan(%Rate{rate: rate, interval: interval, ramp: %Ramp{target: target} = ramp}) do
      %{
        throttle: %{from_rate: rate, to_rate: target, interval: interval},
        plan: Ramp.to_amoc_gradual_plan(ramp)
      }
    end
  end
end
