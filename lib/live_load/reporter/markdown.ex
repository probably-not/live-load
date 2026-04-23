defmodule LiveLoad.Reporter.Markdown do
  @moduledoc """
  `LiveLoad.Reporter.Markdown` is a very very simple Markdown-based reporter
  that can be used to just inspect the outputs of a run in a basic markdown report.
  """

  alias LiveLoad.Result

  @quantiles [p50: 50, p90: 90, p95: 95, p99: 99]

  @doc """
  Render a markdown report from the result of `LiveLoad.run/1`.

  Returns a `t:binary/0` which can then be used to write to a file, served over a web server, etc.
  """
  @spec render!(results :: %{LiveLoad.Scenario.t() => LiveLoad.scenario_result()}) :: binary()
  def render!(results) when is_map(results) do
    IO.iodata_to_binary([
      "# LiveLoad Report\n",
      "Generated: #{DateTime.to_iso8601(DateTime.utc_now())}\n",
      Enum.map_join(results, "\n---\n\n", &scenario_section/1)
    ])
  end

  defp scenario_section({_scenario, {:error, reason}}) do
    "## Error\n\n**ERROR**: `#{inspect(reason)}`\n"
  end

  defp scenario_section({_scenario, %Result{} = result}) do
    [
      "## #{result.name}\n\n",
      "### Global\n\n",
      scenario_result_section(result.global),
      "\n",
      Enum.map_join(result.nodes, "\n", &node_section/1)
    ]
  end

  defp node_section(%Result.NodeResult{status: :error, node: node}) do
    "### #{node}\n\n**ERROR**: node failed during load test\n"
  end

  defp node_section(%Result.NodeResult{status: :ok, node: node, result: scenario_result}) do
    [
      "### #{node}\n\n",
      scenario_result_section(scenario_result)
    ]
  end

  defp scenario_result_section(%Result.ScenarioResult{} = sr) do
    [
      users_summary(sr.users),
      "\n",
      histograms_section(sr.histograms),
      counters_section(sr.counters)
    ]
  end

  defp users_summary(%Result.Users{total: total, succeeded: succeeded, failed: failed}) do
    "**Users**: #{total} total, #{succeeded} succeeded, #{failed} failed\n"
  end

  defp histograms_section(histograms) when map_size(histograms) == 0, do: ""

  defp histograms_section(histograms) do
    header = "| Metric | Count | Min | p50 | p90 | p95 | p99 | Max | Mean |\n"
    separator = "|--------|------:|----:|----:|----:|----:|----:|----:|-----:|\n"

    rows =
      histograms
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join(fn {name, %Result.DimensionedHistogram{} = dh} ->
        [
          quantiles_row(name, dh.aggregate),
          dimensional_rows(dh.by)
        ]
      end)

    ["\n#### Histograms\n\n", header, separator, rows]
  end

  defp dimensional_rows(by) when map_size(by) == 0, do: ""

  defp dimensional_rows(by) do
    by
    |> Enum.sort_by(fn {dim, _} -> dim end)
    |> Enum.map_join(fn {dimension, pq} ->
      quantiles_row("  #{dimension}", pq)
    end)
  end

  defp quantiles_row(label, %Result.PrecomputedQuantiles{count: 0}) do
    "| #{label} | 0 | - | - | - | - | - | - | - |\n"
  end

  defp quantiles_row(label, %Result.PrecomputedQuantiles{} = pq) do
    mean = Float.round(pq.sum / pq.count, 1)

    quantile_values =
      Enum.map_join(@quantiles, " | ", fn {_label, idx} ->
        format_number(Enum.at(pq.values, idx))
      end)

    min = format_number(Enum.at(pq.values, 0))
    max = format_number(Enum.at(pq.values, 100))

    "| #{label} | #{pq.count} | #{min} | #{quantile_values} | #{max} | #{format_number(mean)} |\n"
  end

  defp counters_section(counters) when map_size(counters) == 0, do: ""

  defp counters_section(counters) do
    header = "| Counter | Value |\n"
    separator = "|---------|------:|\n"

    rows =
      counters
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join(fn {name, %Result.DimensionedCounter{} = dc} ->
        [
          "| #{name} | #{dc.aggregate} |\n",
          dimensional_counter_rows(dc.by)
        ]
      end)

    ["\n#### Counters\n\n", header, separator, rows]
  end

  defp dimensional_counter_rows(by) when map_size(by) == 0, do: ""

  defp dimensional_counter_rows(by) do
    by
    |> Enum.sort_by(fn {dim, _} -> dim end)
    |> Enum.map_join(fn {dimension, value} ->
      "|   #{dimension} | #{value} |\n"
    end)
  end

  defp format_number(n) when is_float(n), do: n |> Float.round(1) |> to_string()
  defp format_number(n) when is_integer(n), do: to_string(n)
  defp format_number(_), do: "-"
end
