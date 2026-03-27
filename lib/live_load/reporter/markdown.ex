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

  @quantiles [p50: 0.5, p90: 0.9, p95: 0.95, p99: 0.99]

  def write!(results, path \\ "liveload_report.md") do
    markdown =
      IO.iodata_to_binary([
        "# LiveLoad Report\n",
        "Generated: #{DateTime.to_iso8601(DateTime.utc_now())}\n",
        Enum.map_join(results, "\n---\n\n", &scenario_section/1)
      ])

    File.write!(path, markdown)
  end

  defp scenario_section({scenario, node_results}) do
    [
      "## #{inspect(scenario)}\n\n",
      Enum.map_join(node_results, "\n", &node_section/1)
    ]
  end

  defp node_section({node, {:error, reason}}) do
    "### #{node}\n\n**ERROR**: `#{inspect(reason)}`\n"
  end

  defp node_section({node, %LiveLoad.Result{} = result}) do
    [
      "### #{node}\n\n",
      users_summary(result),
      "\n",
      sketches_section(result.sketches),
      counters_section(result.counters)
    ]
  end

  defp users_summary(%{total: total, succeeded: succeeded, failed: failed}) do
    "**Users**: #{total} total, #{succeeded} succeeded, #{failed} failed\n"
  end

  defp sketches_section(sketches) when map_size(sketches) == 0, do: ""

  defp sketches_section(sketches) do
    {aggregate, dimensional} =
      Enum.split_with(sketches, fn {key, _} -> is_atom(key) end)

    [
      aggregate_sketches_table(aggregate),
      dimensional_sketches_sections(dimensional)
    ]
  end

  defp aggregate_sketches_table([]), do: ""

  defp aggregate_sketches_table(sketches) do
    header = "| Metric | Count | Min | p50 | p90 | p95 | p99 | Max | Mean |\n"
    separator = "|--------|------:|----:|----:|----:|----:|----:|----:|-----:|\n"

    rows =
      sketches
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join(fn {name, sketch} ->
        sketch_row(Atom.to_string(name), sketch)
      end)

    ["\n#### Sketches\n\n", header, separator, rows]
  end

  defp dimensional_sketches_sections([]), do: ""

  defp dimensional_sketches_sections(dimensional) do
    dimensional
    |> Enum.group_by(fn {{name, _dimension}, _sketch} -> name end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join(fn {name, entries} ->
      header = "| #{Atom.to_string(name)} | Count | Min | p50 | p90 | p95 | p99 | Max | Mean |\n"
      separator = "|--------|------:|----:|----:|----:|----:|----:|----:|-----:|\n"

      rows =
        entries
        |> Enum.sort_by(fn {{_, dim}, _} -> dim end)
        |> Enum.map_join(fn {{_, dimension}, sketch} ->
          sketch_row(dimension, sketch)
        end)

      ["\n##### By dimension: `#{name}`\n\n", header, separator, rows]
    end)
  end

  defp sketch_row(label, sketch) do
    count = :ddskerl_std.total(sketch)

    if count == 0 do
      "| #{label} | 0 | - | - | - | - | - | - | - |\n"
    else
      sum = :ddskerl_std.sum(sketch)
      mean = Float.round(sum / count, 1)

      quantile_values =
        Enum.map(@quantiles, fn {_label, q} ->
          format_number(:ddskerl_std.quantile(sketch, q))
        end)

      min = format_number(:ddskerl_std.quantile(sketch, 0.0))
      max = format_number(:ddskerl_std.quantile(sketch, 1.0))

      "| #{label} | #{count} | #{min} | #{Enum.join(quantile_values, " | ")} | #{max} | #{format_number(mean)} |\n"
    end
  end

  defp counters_section(counters) when map_size(counters) == 0, do: ""

  defp counters_section(counters) do
    {aggregate, dimensional} =
      Enum.split_with(counters, fn {key, _} -> is_atom(key) end)

    [
      aggregate_counters_table(aggregate),
      dimensional_counters_sections(dimensional)
    ]
  end

  defp aggregate_counters_table([]), do: ""

  defp aggregate_counters_table(counters) do
    header = "| Counter | Value |\n"
    separator = "|---------|------:|\n"

    rows =
      counters
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join(fn {name, value} ->
        "| #{name} | #{value} |\n"
      end)

    ["\n#### Counters\n\n", header, separator, rows]
  end

  defp dimensional_counters_sections([]), do: ""

  defp dimensional_counters_sections(dimensional) do
    dimensional
    |> Enum.group_by(fn {{name, _}, _} -> name end)
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join(fn {name, entries} ->
      header = "| #{Atom.to_string(name)} | Value |\n"
      separator = "|---------|------:|\n"

      rows =
        entries
        |> Enum.sort_by(fn {{_, dim}, _} -> dim end)
        |> Enum.map_join(fn {{_, dimension}, value} ->
          "| #{dimension} | #{value} |\n"
        end)

      ["\n##### By dimension: `#{name}`\n\n", header, separator, rows]
    end)
  end

  defp format_number(:undefined), do: "-"
  defp format_number(n) when is_float(n), do: n |> Float.round(1) |> to_string()
end
