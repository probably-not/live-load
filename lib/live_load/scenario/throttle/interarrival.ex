defmodule LiveLoad.Scenario.Throttle.Interarrival do
  @moduledoc """
  `LiveLoad.Scenario.Throttle.Interarrival` provides a rate limiter which enforces a set amount of time between events.

  ## Examples

  ```elixir
  # One event every 500 milliseconds
  #{inspect(__MODULE__)}.new(:my_throttle, to_timeout(millisecond: 500))

  # One event every 2 seconds
  #{inspect(__MODULE__)}.new(:my_throttle, to_timeout(second: 2))

  # Start at 1 event per second and ramp up over the next 2 minutes
  #{inspect(__MODULE__)}.new(:my_throttle, to_timeout(second: 1))
  |> #{inspect(__MODULE__)}.ramp(100, duration: to_timeout(minute: 2))
  ```
  """
  alias __MODULE__
  alias LiveLoad.Scenario.Throttle.Ramp

  @type time_between() :: pos_integer()

  @opaque t() :: %__MODULE__{
            name: atom(),
            time_between: time_between(),
            ramp_opts: [Ramp.option()] | nil,
            ramp: Ramp.t() | nil
          }

  @enforce_keys [:name, :time_between]
  defstruct [:name, :time_between, :ramp_opts, :ramp]

  @doc """
  Creates a new `LiveLoad.Scenario.Throttle.Interarrival` with the given name and time between events.
  """
  @spec new(name :: atom(), time_between :: time_between()) :: t()
  def new(name, time_between) when is_atom(name) and not is_nil(name) and is_integer(time_between) and time_between > 0 do
    %__MODULE__{name: name, time_between: time_between}
  end

  @doc """
  Attaches a gradually ramping interarrival change to the throttle.

  Target defines the target interarrival in milliseconds.

  ## Options

    * `:duration`: The duration of the gradual ramp up in milliseconds
    * `:steps`: The number of steps to take while ramping up. Requires am `:interval` value.
    * `:interval`: The interval at which to take each step. Requires a `:step` value.
  """
  @spec ramp(interarrival :: t(), target :: Ramp.target(), ramp_opts :: [Ramp.option()]) :: t()
  def ramp(%__MODULE__{} = interarrival, target, opts) when is_list(opts) do
    %{interarrival | ramp_opts: [{:target, target} | opts]}
  end

  defimpl LiveLoad.Scenario.Throttle do
    def name(%Interarrival{name: name}), do: name

    def validate(%Interarrival{name: nil} = interarrival) do
      {:error, {:missing_name, interarrival}}
    end

    def validate(%Interarrival{name: name, time_between: time_between})
        when not (is_integer(time_between) and time_between > 0) do
      {:error, {:invalid_interarrival, name, time_between}}
    end

    def validate(%Interarrival{ramp_opts: nil} = interarrival), do: {:ok, interarrival}

    def validate(%Interarrival{ramp_opts: opts} = interarrival) do
      case Ramp.build(opts) do
        %Ramp{} = ramp ->
          {:ok, %{interarrival | ramp: ramp}}

        {:error, reason} ->
          {:error, {:invalid_ramp_opts, reason}}
      end
    end

    def to_amoc_config(%Interarrival{time_between: time_between}) do
      %{interarrival: time_between}
    end

    def to_amoc_gradual_plan(%Interarrival{ramp: nil}), do: nil

    def to_amoc_gradual_plan(%Interarrival{time_between: time_between, ramp: %Ramp{target: target} = ramp}) do
      %{
        throttle: %{from_interarrival: time_between, to_interarrival: target},
        plan: Ramp.to_amoc_gradual_plan(ramp)
      }
    end
  end
end
