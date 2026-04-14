defmodule LiveLoad.Scenario.Throttle.Parallelism do
  @moduledoc """
  `LiveLoad.Scenario.Throttle.Parallelism` provides a throttle that ensures only a certain amount of parallel executions at any given time.

  ## Example

  ```elixir
  #{__MODULE__}.new(:my_throttle, 5)
  ```
  """

  alias __MODULE__

  @opaque t() :: %__MODULE__{
            name: atom(),
            limit: pos_integer()
          }

  @enforce_keys [:name, :limit]
  defstruct [:name, :limit]

  @doc """
  Creates a new `LiveLoad.Scenario.Throttle.Parallelism` with the given name and concurrency limit.
  """
  @spec new(name :: atom(), limit :: pos_integer()) :: t()
  def new(name, limit) when is_atom(name) and not is_nil(name) and is_integer(limit) and limit > 0 do
    %__MODULE__{name: name, limit: limit}
  end

  defimpl LiveLoad.Scenario.Throttle do
    def name(%Parallelism{name: name}), do: name

    def validate(%Parallelism{name: nil} = parallelism) do
      {:error, {:missing_name, parallelism}}
    end

    def validate(%Parallelism{name: name, limit: limit}) when not (is_integer(limit) and limit > 0) do
      {:error, {:invalid_parallelism, name, limit}}
    end

    def validate(%Parallelism{} = throttle), do: {:ok, throttle}

    def to_amoc_config(%Parallelism{limit: limit}) do
      %{rate: limit, interval: 0}
    end

    def to_amoc_gradual_plan(%Parallelism{}), do: nil
  end
end
