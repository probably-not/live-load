# Changelog for v0.1

The first public release of LiveLoad.

I'm trying to model this changelog around how I've seen the Phoenix and Elixir changelogs modeled. I quite like how they're structured, so I've structured mine in a similar way. Hopefully you enjoy reading it!

For the full development journey (and basically my personal development diary) from an empty repo to this release, see the [Devlog](./DEVLOG.md).

If you are just getting started with LiveLoad, the [Writing Your First Scenario](https://hexdocs.pm/live_load/writing_your_first_scenario.html) guide is the best place to start. It covers everything from basic navigation to throttles, assigns, and the full scenario lifecycle.

## Scenario API

LiveLoad scenarios are defined as modules implementing the `LiveLoad.Scenario` behaviour. The `use LiveLoad.Scenario` macro sets up the behaviour, imports all context functions, and provides default implementations for optional callbacks.

A scenario has three callbacks:

- `c:LiveLoad.Scenario.config/1`: Called once per node. Receives any unconsumed options from `LiveLoad.run/1` and returns a config value forwarded to every `c:LiveLoad.Scenario.run/3` call.
- `c:LiveLoad.Scenario.throttles/1`: Called once per node. Returns a list of cluster-wide throttles for this scenario.
- `c:LiveLoad.Scenario.run/3`: The actual load test. Called in a loop per user until `:scenario_duration` expires.

A minimal example scenario looks something like this:

```elixir
defmodule MyApp.Scenarios.Dashboard do
  use LiveLoad.Scenario

  @impl true
  def run(ctx, _user_id, _config) do
    ctx
    |> navigate("https://myapp.com/dashboard")
    |> wait_for_liveview()
    |> click("#refresh_data")
    |> wait_for_phx_loading_completion(:click, "#refresh_data")
    |> fill("#search", "test query")
    |> submit_form("#search-form")
  end
end
```

## Context pipeline

`LiveLoad.Scenario.Context` is modeled on `Plug.Conn`. It flows through a pipeline of browser operations, and if any step fails, the rest of the pipeline is skipped automatically. The error is captured on the context and reported by the runner.

The context supports assigns (persisted across iterations), resolvable values (1-arity functions receiving the context), and an `:as` option on extraction functions for assigning values from the page onto the context:

```elixir
def run(ctx, user_id, config) do
  ctx
  |> navigate("#{config.base_url}/products")
  |> wait_for_liveview()
  |> get_attribute("#product", "data-id", as: :product_id)
  |> click(&"#add-to-cart-#{&1.assigns.product_id}")
  |> wait_for_phx_loading_completion(:click, &"#add-to-cart-#{&1.assigns.product_id}")
end
```

## LiveView-aware metrics

LiveLoad injects a JavaScript observer into every browser context via Playwright's `addInitScript`. This observer watches the DOM for LiveView's loading classes (`phx-click-loading`, `phx-submit-loading`, etc.) and emits timing telemetry when they are added and removed. This is how `LiveLoad.Scenario.Context.wait_for_phx_loading_completion/3` measures the real time between "I clicked" and "the UI responded", from the browser's perspective.

HTTP request/response metrics and WebSocket frame sizes and rates are collected via PlaywrightEx's protocol subscription mechanism.

> #### WebSocket vs Longpolling Transports {: .info}
>
> Phoenix.Socket-level metrics (frame sizes, frame rates) are collected cleanly over WebSocket connections.
> If your app falls back to longpolling, those frame-level metrics won't be captured directly, since longpolling
> is just HTTP from the browser's perspective. Browser-level LiveView metrics (mount times, `phx-*-loading`
> durations) are recorded regardless of transport.

## Distributed load testing

LiveLoad uses [`:amoc`](https://github.com/esl/amoc) for distributed user simulation and [`FLAME`](https://github.com/phoenixframework/flame) for elastic node orchestration. When `distributed?: true` is set, `LiveLoad.Cluster` calculates the necessary node count based on available resources, primes the cluster eagerly via `FLAME.call`, and tears it all down when the test completes.

```elixir
LiveLoad.run(
  otp_app: :my_app,
  users: 1_000,
  distributed?: true,
  flame_backend: FLAME.FlyBackend,
  cluster_opts: [
    flame_backend_opts: [app: :my_runner, cpus: 8, memory_mb: 16 * 1024],
    max_allowed_nodes: 100
  ]
)
```

## Throttles

Three throttle types are available, all cluster-wide via `:amoc_throttle`:

- `LiveLoad.Scenario.Throttle.Rate`: A basic rate limiter which limits to a specific number of events per interval configured.
- `LiveLoad.Scenario.Throttle.Interarrival`: A rate limiter which defines the amount of time between each event.
- `LiveLoad.Scenario.Throttle.Parallelism`: A rate limiter which ensures a specific number of concurrent executions.

`Rate` and `Interarrival` support gradual ramp-ups via `:duration` or `:steps` + `:interval`:

```elixir
def throttles(_config) do
  [
    :visitors |> Rate.new(10) |> Rate.ramp(100, duration: to_timeout(minute: 5))
  ]
end
```

## Results and reporters

`LiveLoad.Result` is a compact, JSON-serializable struct containing 101-point precomputed quantile curves, dimensioned histograms and counters, time-series buckets, and per-node breakdowns. Reporters don't need to know anything about LiveLoad's internals, the entire serialized result is precomputed.

Two reporters ship with this release:

- `LiveLoad.Reporter.HTML`: a self-contained single-file HTML report with an embedded React SPA. Run data is gzipped and base64 encoded into the page.
- `LiveLoad.Reporter.Markdown`: a simple tabular output for quick inspection.

```elixir
results = LiveLoad.run(otp_app: :my_app, users: 50)

html = LiveLoad.Reporter.HTML.render!(results)
File.write!("liveload_report.html", html)
```

## v0.1.0 (2026-04-23)

### Enhancements

#### Core

  * [LiveLoad] Add `LiveLoad.run/1` as the main entrypoint for running load tests
  * [LiveLoad.Scenario] Add behaviour for defining load test scenarios with `config/1`, `throttles/1`, and `run/3` callbacks
  * [LiveLoad.Scenario] Add `use LiveLoad.Scenario` macro that sets up the behaviour, imports context functions, and provides default callback implementations
  * [LiveLoad.Scenario.Runner] Add `gen_statem` based scenario runner that loops `run/3` until duration expires, halt, or failure
  * [LiveLoad.Scenario.Discovery] Add various levels of automatic scenario discovery to allow running scenarios in different ways

#### Scenario Context

  * [LiveLoad.Scenario.Context] Add `Plug.Conn` inspired pipeline struct with automatic error short-circuiting
  * [LiveLoad.Scenario.Context] Add navigation functions: `navigate/2`, `reload/1`
  * [LiveLoad.Scenario.Context] Add element interaction functions: `click/2`, `fill/3`, `clear/2`, `press/3`, `check/2`, `uncheck/2`, `select_option/3`, `select_multiple_options/3`, `focus/2`, `blur/2`, `hover/2`, `drag_and_drop/3`, `wait_for_selector/2`
  * [LiveLoad.Scenario.Context] Add LiveView specific functions: `ensure_liveview/1`, `wait_for_liveview/1`, `wait_for_phx_loading_completion/3`, `submit_form/2`
  * [LiveLoad.Scenario.Context] Add value extraction functions with `:as` option: `page_content/2`, `inner_html/3`, `inner_text/3`, `text_content/3`, `input_value/3`, `get_attribute/4`, `visible?/3`, `checked?/3`
  * [LiveLoad.Scenario.Context] Add assigns management: `assign/3`, `reset_assigns/1`, `clear_assign/2`, `update_assign!/3`
  * [LiveLoad.Scenario.Context] Add flow control: `halt/1`, `fail/2`, `halted?/1`, `failed?/1`
  * [LiveLoad.Scenario.Context] Add browser storage functions: `context_storage_snapshot/2`, `restore_context_storage/2`, `reset_context_storage/1`
  * [LiveLoad.Scenario.Context] Support resolvable values (1-arity functions receiving the context) for selectors, URLs, and values

#### Throttles

  * [LiveLoad.Scenario.Throttle.Rate] Add rate limiter with configurable interval and gradual ramp-up support
  * [LiveLoad.Scenario.Throttle.Interarrival] Add interarrival-based throttle with gradual ramp-up support
  * [LiveLoad.Scenario.Throttle.Parallelism] Add concurrency limiter

#### Browser

  * [LiveLoad.Browser] Add browser abstraction with pluggable `LiveLoad.Browser.Connection` behaviour
  * [LiveLoad.Browser.Connection.Playwright] Add Playwright based browser connection using PlaywrightEx
  * [Mix.Tasks.LiveLoad.Install] Add `mix live_load.install` task to download the Playwright standalone driver and Chromium binaries

#### Distribution

  * [LiveLoad.Cluster] Add FLAME based elastic cluster formation with automatic node count calculation based on resource availability
  * [LiveLoad.Cluster.Node] Add `FLAME.Trackable` node struct for eager cluster priming
  * [LiveLoad.Cluster.AmocSeed] Add parallel cluster seeding with direct pinging to work around gossip deadlocks on larger clusters

#### Telemetry and Results

  * [LiveLoad.Telemetry.Listener] Add per node telemetry listener collecting metrics into DDSketch structures via `ddskerl`
  * [LiveLoad.Telemetry.Collector] Add primary node collector that merges sketches from all nodes into a single result
  * [LiveLoad.Result] Add compact, JSON-serializable result struct with 101-point precomputed quantile curves, dimensioned histograms and counters, time-series buckets, and per-node breakdowns

#### Reporters

  * [LiveLoad.Reporter.Markdown] Add simple tabular markdown reporter
  * [LiveLoad.Reporter.HTML] Add self-contained single-file HTML reporter with embedded React/TypeScript SPA
