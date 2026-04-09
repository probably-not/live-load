defmodule LiveLoad.Reporter.Markdown do
  @moduledoc false
  # `LiveLoad.Reporter.Markdown` is a very very simple Markdown-based reporter
  # that is being used to just inspect the outputs of a run. The `LiveLoad.Result`
  # struct contains the final output of a run, but with all of the metrics that I'm
  # adding and collecting, it's... a lot. So I needed a simple reporting mechanism.
  # TODO: Real UI is a huge thing here. I'm not a big UI person, so I will probably
  # end up delegating the UI concept and generation to Claude. I find that Claude is
  # quite good at generating the classic UI formats, so instead of me breaking my head
  # trying to figure out the best way to display things in nice charts, I'll let Claude
  # take care of that. A good amount of the markdown generation here was already generated
  # by Claude Opus 4.6 for me - I gave it the structure of `LiveLoad.Result` and told it
  # to create a debugging Markdown script that gives me a report I can use.

  alias LiveLoad.Result

  @quantiles [p50: 50, p90: 90, p95: 95, p99: 99]

  def write!(results, path \\ "liveload_report.md") do
    markdown =
      IO.iodata_to_binary([
        "# LiveLoad Report\n",
        "Generated: #{DateTime.to_iso8601(DateTime.utc_now())}\n",
        Enum.map_join(results, "\n---\n\n", &scenario_section/1)
      ])

    File.write!(path, markdown)
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
