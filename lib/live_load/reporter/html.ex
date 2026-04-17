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

    payload = encode_payload(results)

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

  # With the exploded results we are hitting V8's string limits with just absolutely gigantic json structures...
  # If the JSON is going to be huge, this will trim it into something manageable.
  @max_json_bytes 400 * 1024 * 1024

  defp encode_payload(results) do
    entries =
      Enum.map(results, fn
        {_scenario, %LiveLoad.Result{} = result} ->
          result

        {scenario, {:error, reason}} ->
          %{name: inspect(scenario), error: inspect(reason, limit: :infinity, printable_limit: :infinity, pretty: true)}

        unknown ->
          %{
            name: "unknown_result_value",
            value: inspect(unknown, limit: :infinity, printable_limit: :infinity, pretty: true)
          }
      end)

    json = LiveLoad.JSON.encode!(entries)

    json =
      if byte_size(json) > @max_json_bytes do
        entries
        |> trim_data_to_significant_quantiles()
        |> LiveLoad.JSON.encode_to_iodata!()
        |> IO.iodata_to_binary()
      else
        json
      end

    json
    |> :zlib.gzip()
    |> Base.encode64()
  end

  defp trim_data_to_significant_quantiles(results) do
    Enum.map(results, fn
      {scenario, %LiveLoad.Result{} = result} ->
        {scenario, trim_result(result)}

      other ->
        other
    end)
  end

  defp trim_result(%LiveLoad.Result{} = result) do
    %{result | global: trim_scenario_result(result.global), nodes: Enum.map(result.nodes, &trim_node_result/1)}
  end

  defp trim_node_result(%LiveLoad.Result.NodeResult{status: :ok, result: result} = node_result) do
    %{node_result | result: trim_scenario_result(result)}
  end

  defp trim_node_result(node_result), do: node_result

  defp trim_scenario_result(%LiveLoad.Result.ScenarioResult{} = result) do
    %{result | time_series: Enum.map(result.time_series, &trim_bucket/1)}
  end

  defp trim_bucket(%LiveLoad.Result.Bucket{} = bucket) do
    histograms =
      Map.new(bucket.histograms, fn {k, dh} ->
        {k, trim_dimensioned_histogram(dh)}
      end)

    %{bucket | histograms: histograms}
  end

  defp trim_dimensioned_histogram(%LiveLoad.Result.DimensionedHistogram{} = histogram) do
    by = Map.new(histogram.by, fn {k, quantiles} -> {k, trim_quantiles(quantiles)} end)
    %{histogram | aggregate: trim_quantiles(histogram.aggregate), by: by}
  end

  @significant_quantiles [50, 95, 99, 100]

  defp trim_quantiles(%LiveLoad.Result.PrecomputedQuantiles{} = quantiles) do
    %{quantiles | values: Enum.map(@significant_quantiles, &Enum.at(quantiles.values, &1))}
  end
end
