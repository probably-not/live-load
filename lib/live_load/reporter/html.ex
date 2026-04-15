defmodule LiveLoad.Reporter.HTML do
  @moduledoc """
  `LiveLoad.Reporter.HTML` provides a self-contained HTML report that embeds a set of `LiveLoad.Result` structs from a load test.

  The HTML template is prebuilt as a single file and the JSON encoded data is stored in the page. Due to how `LiveLoad.Result` is
  built and encoded, this may generate a very large file. The code that builds the template can be found in the `react-reporter`
  directory in the LiveLoad repository.

  The reporter returns an `t:binary/0` which can be served by a server, written to a file, transmitted somewhere else, etc.
  """

  @template_data_placeholder "__LIVELOAD_DATA_INJECTION_POINT_DO_NOT_REMOVE__"

  @doc """
  Render an HTML report from the result of `LiveLoad.run/1`.

  Returns a `t:binary/0` which can then be used to write to a file, served over a web server, etc.
  """
  @spec render!(results :: %{LiveLoad.Scenario.t() => LiveLoad.scenario_result()}) :: binary()
  def render!(results) when is_map(results) do
    path = Application.app_dir(:live_load, Path.join(["priv", "react-reporter", "template.html"]))
    template = File.read!(path)

    payload =
      results
      |> Enum.map(fn
        {_scenario, %LiveLoad.Result{} = result} ->
          result

        {scenario, {:error, reason}} ->
          %{name: inspect(scenario), error: inspect(reason, limit: :infinity, printable_limit: :infinity, pretty: true)}

        unknown ->
          %{
            name: "unkown_result_value",
            value: inspect(unknown, limit: :infinity, printable_limit: :infinity, pretty: true)
          }
      end)
      |> LiveLoad.JSON.encode_to_iodata!()
      |> IO.iodata_to_binary()
      |> :zlib.gzip()
      |> Base.encode64()

    case :binary.match(template, @template_data_placeholder) do
      :nomatch ->
        raise RuntimeError, """
        `LiveLoad.Reporter.HTML` template is missing the data
        placeholder for injecting run data into the template.
        """

      {_, _} ->
        :binary.replace(template, @template_data_placeholder, payload)
    end
  end
end
