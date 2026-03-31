defmodule LiveLoad.JSON do
  @moduledoc """
  `LiveLoad.JSON` is a simple delegation module which delegates to one of a few optional JSON parsers.
  `LiveLoad` requires JSON decoding for decoding certain messages via the browser protocol.

  If you are running an Elixir version above (and including) 1.18, this will automatically use the `Elixir.JSON`
  built-in module for decoding.

  If you are running an Elixir version below (and including) 1.17, you must install one of the optional JSON libraries
  such as `Jason` or `Poison`.

  This delegation module will be necessary until Elixir version 1.22 is fully released and this library is updated to work with
  only Elixir versions above 1.18, which is when `Elixir.JSON` was first introduced.
  """

  cond do
    Code.ensure_loaded?(Elixir.JSON) ->
      defdelegate decode(args), to: Elixir.JSON

    Code.ensure_loaded?(Jason) ->
      defdelegate decode(args), to: Jason

    Code.ensure_loaded?(Poison) ->
      defdelegate decode(args), to: Poison

    true ->
      raise CompileError, """
      LiveLoad requires JSON decoding for decoding certain messages via the browser protocol.

      If you are running an Elixir version above (and including) 1.18, this will automatically use the `Elixir.JSON`
      built-in module for decoding.

      If you are running an Elixir version below (and including) 1.17, you must install one of the optional JSON libraries
      such as Jason or Poison.
      """
  end

  defmacro derive_encoder(opts \\ []) do
    cond do
      Code.ensure_loaded?(Elixir.JSON) ->
        quote do
          @derive {JSON.Encoder, unquote(opts)}
        end

      Code.ensure_loaded?(Jason) ->
        quote do
          @derive {Jason.Encoder, unquote(opts)}
        end

      Code.ensure_loaded?(Poison) ->
        quote do
          @derive {Poison.Encoder, unquote(opts)}
        end

      true ->
        raise CompileError, """
        LiveLoad requires JSON encoding in order to serialize certain data structures for consumption by other libraries.

        If you are running an Elixir version above (and including) 1.18, this will automatically use the `Elixir.JSON`
        built-in module for decoding.

        If you are running an Elixir version below (and including) 1.17, you must install one of the optional JSON libraries
        such as Jason or Poison.
        """
    end
  end
end
