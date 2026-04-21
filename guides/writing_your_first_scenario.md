# Writing Your First Scenario

A `LiveLoad.Scenario` is a module that describes what a simulated user does on your site. You write what a user would do:

- Navigate to a page, 
- Click around
- Fill out a form

and LiveLoad handles the rest for you:

- Spinning up real browser contexts
- Running your scenario in a loop
- Collecting metrics, a
- And tearing everything down when the test is over

If you've ever used `Plug.Conn`, the API should feel familiar. The scenario context flows through a pipeline of operations, and if anything goes wrong, the pipeline short-circuits automatically.

## The Basics

A scenario module needs three things: `use LiveLoad.Scenario`, a `c:LiveLoad.Scenario.run/3` callback, and that's it. 

```elixir
defmodule MyApp.LoadTest.HomepageScenario do
  use LiveLoad.Scenario

  @impl true
  def run(context, _user_id, _config) do
    context
    |> navigate("https://myapp.com/")
    |> wait_for_liveview()
  end
end
```

The `use LiveLoad.Scenario` macro sets up the behaviour, imports all of the context functions you'll need, and defines default implementations for the optional callbacks so you don't have to.

To run it:

```elixir
LiveLoad.run(
  scenario: MyApp.LoadTest.HomepageScenario,
  users: 10,
  scenario_duration: to_timeout(minute: 2)
)
```

This will start 10 simulated users, each in their own isolated browser context, and loop the scenario for 2 minutes.

## The Scenario Lifecycle

Here's what happens when your scenario runs:

1. **`c:LiveLoad.Scenario.config/1`** is called once per node with any extra options you passed to `LiveLoad.run/1`. It returns a config value that gets passed to every `c:LiveLoad.Scenario.run/3` call.
2. **`c:LiveLoad.Scenario.throttles/1`** is called once per node with the config from step 1. It returns a list of throttles to register for this scenario (more on these later).
3. Each user gets its own `LiveLoad.Scenario.Context` wrapping an isolated `LiveLoad.Browser.Context`.
4. **`c:LiveLoad.Scenario.run/3`** is called in a loop for each user, receiving the context, user ID, and config. The loop continues until the configured `:scenario_duration` has elapsed.
5. The context returned from one iteration of `c:LiveLoad.Scenario.run/3` becomes the input to the next iteration. Assigns survive across iterations! You can use data from a previous iteration in the next one.
6. Once the duration expires, the current iteration finishes and the user process terminates cleanly.

Both `c:LiveLoad.Scenario.config/1` and `c:LiveLoad.Scenario.throttles/1` have default implementations that return `{:ok, %{}}` and `[]` respectively, so you only need to override them if you actually need configuration or throttling.

## The `c:LiveLoad.Scenario.config/1` Callback

Any options you pass to `LiveLoad.run/1` that aren't consumed by LiveLoad itself get forwarded to `c:LiveLoad.Scenario.config/1`. This is how you pass scenario-specific settings like a base URL, credentials, or test data.

```elixir
defmodule MyApp.LoadTest.LoginScenario do
  use LiveLoad.Scenario

  @impl true
  def config(opts) do
    {:ok, %{base_url: opts[:base_url] || "https://myapp.com"}}
  end

  @impl true
  def run(context, _user_id, config) do
    context
    |> navigate("#{config.base_url}/login")
    |> wait_for_liveview()
    |> fill("#email", "loadtest@example.com")
    |> fill("#password", "password123")
    |> submit_form("#login-form")
  end
end
```

Then pass the config when running:

```elixir
LiveLoad.run(
  scenario: MyApp.LoadTest.LoginScenario,
  users: 25,
  base_url: "https://staging.myapp.com"
)
```

## The Context Pipeline

The `LiveLoad.Scenario.Context` is the core of how you write scenarios. It flows through your pipeline,
and every operation either succeeds and returns an updated context, or fails and marks the context with an error. Once a context has an error (or has been halted), all subsequent operations are no-ops, so the context just passes through untouched.

This means you can write a long pipeline without worrying about error handling at each step:

```elixir
def run(context, _user_id, _config) do
  context
  |> navigate("https://myapp.com/products")
  |> wait_for_liveview()
  |> click("#product-1")
  |> wait_for_phx_loading_completion(:click, "#product-1")
  |> click("#add-to-cart")
  |> wait_for_phx_loading_completion(:click, "#add-to-cart")
  |> navigate("https://myapp.com/cart")
  |> wait_for_liveview()
end
```

If the `LiveLoad.Scenario.Context.click/2` call fails (maybe the element doesn't exist), everything after it is skipped. The error gets recorded on the context, and the runner captures it for reporting.

## Navigation

Two functions for getting around:

- `LiveLoad.Scenario.Context.navigate/2`: navigates to the given URL.
- `LiveLoad.Scenario.Context.reload/1`: reloads the current page.

```elixir
context
|> navigate("https://myapp.com/dashboard")
|> reload()
```

## Interacting With Elements

All element interactions take a CSS selector to find the element on the page.

### Clicking

```elixir
click(context, "#submit-button")
click(context, "button[data-action='save']")
```

### Filling Inputs

```elixir
fill(context, "#email", "user@example.com")
fill(context, "#search", "elixir load testing")
```

Passing an empty string clears the input. There's also a dedicated `LiveLoad.Scenario.Context.clear/2` that does the same thing:

```elixir
clear(context, "#search")
```

### Keyboard Input

`LiveLoad.Scenario.Context.press/3` focuses an element and activates a key:

```elixir
press(context, "#search", "Enter")
```

### Checkboxes and Radio Buttons

```elixir
check(context, "#agree-to-terms")
uncheck(context, "#marketing-emails")
```

### Select Dropdowns

```elixir
select_option(context, "#country", "US")
select_multiple_options(context, "#tags", ["elixir", "phoenix", "liveview"])
```

### Focus, Blur, Hover

```elixir
focus(context, "#email")
blur(context, "#email")
hover(context, "#tooltip-trigger")
```

### Drag and Drop

```elixir
drag_and_drop(context, "#draggable-item", "#drop-zone")
```

### Waiting For Elements

`LiveLoad.Scenario.Context.wait_for_selector/2` waits until an element matching the selector appears on the page:

```elixir
wait_for_selector(context, ".results-loaded")
```

## LiveView-Specific Operations

These are the functions that make LiveLoad different from generic browser automation.

### Detecting and Waiting For LiveView

- `LiveLoad.Scenario.Context.ensure_liveview/1` checks that the current page has a LiveView mounted (it waits for `[data-phx-session]`).
- `LiveLoad.Scenario.Context.wait_for_liveview/1` waits for the LiveView to be fully connected (it waits for `.phx-connected`).

```elixir
context
|> navigate("https://myapp.com/live/dashboard")
|> ensure_liveview()
|> wait_for_liveview()
```

### Waiting For Event Completion

When you trigger a LiveView event (like a click or form submission), Phoenix adds CSS classes like `phx-click-loading` to the target element while the event is in-flight. `LiveLoad.Scenario.Context.wait_for_phx_loading_completion/3` waits for that class to be removed, which means the server has processed the event and the DOM has been patched.

```elixir
context
|> click("#load-more")
|> wait_for_phx_loading_completion(:click, "#load-more")
```

The loading types correspond to the event types that Phoenix uses, which, as of the time of writing are:

- `:click`
- `:submit`
- `:change`
- `:focus`
- `:blur`
- `:keydown`
- `:keyup`

### Submitting Forms

`LiveLoad.Scenario.Context.submit_form/2` is a convenience that clicks the submit button inside a form and then waits for the `phx-submit-loading` class to clear:

```elixir
context
|> fill("#login-form input[name='email']", "user@example.com")
|> fill("#login-form input[name='password']", "secret")
|> submit_form("#login-form")
```

Under the hood, this clicks `#login-form [type=submit]` and then calls `LiveLoad.Scenario.Context.wait_for_phx_loading_completion/3` with `:submit` and the form selector.

## Extracting Values From The Page

Sometimes you need to pull data out of the page. Maybe you need to use it in the next step, or maybe you want to carry it into the next iteration. All extraction functions accept an `:as` option that assigns the extracted value onto the context's assigns.

### Page Content

```elixir
# Extracts the full page content
page_content(context, as: :html)
```

### Element Content

```elixir
# innerHTML of an element
inner_html(context, "#results", as: :results_html)

# innerText of an element (visible text only)
inner_text(context, "#results", as: :results_text)

# textContent of an element (all text, including hidden)
text_content(context, "#results", as: :results_text)
```

### Input Values

```elixir
input_value(context, "#quantity", as: :quantity)
```

### Element Attributes

```elixir
get_attribute(context, "#user-card", "data-user-id", as: :user_id)
```

### Element State

```elixir
visible?(context, "#error-message", as: :has_error)
checked?(context, "#newsletter-opt-in", as: :opted_in)
```

## Assigns

Assigns are a key-value store on the context, just like `Plug.Conn.assigns`. They persist across pipeline steps _and_ across loop iterations, which makes them useful for carrying state forward.

```elixir
def run(context, _user_id, _config) do
  context
  |> navigate("https://myapp.com/products")
  |> wait_for_liveview()
  |> inner_text("#first-product-name", as: :product_name)
  # From now on context.assigns.product_name is available
  |> click("#first-product")
  |> wait_for_phx_loading_completion(:click, "#first-product")
end
```

### Managing Assigns Manually

```elixir
# Set a value
assign(context, :counter, 0)

# Update an existing value (raises KeyError if the key doesn't exist)
update_assign!(context, :counter, &(&1 + 1))

# Clear a specific key
clear_assign(context, :counter)

# Reset all assigns to an empty map
reset_assigns(context)
```

Since the context carries across loop iterations, `LiveLoad.Scenario.Context.reset_assigns/1` is useful when you want each iteration to start clean:

```elixir
def run(context, _user_id, _config) do
  context
  |> reset_assigns()
  |> navigate("https://myapp.com/")
  |> wait_for_liveview()
  # ...
end
```

### The `:as` Option

The `:as` option on extraction functions can take three forms:

**An atom**: assigns the value directly under that key:

```elixir
inner_text(context, "#price", as: :price)
# context.assigns.price => "49.99"
```

**A 1-arity function returning an atom**: lets you compute the key dynamically:

```elixir
inner_html(context, "a", as: fn _value -> :link_html end)
# context.assigns.link_html => "<a href="...">...</a>"
```

**A 1-arity function returning a map**: merges multiple values into assigns at once:

```elixir
inner_html(context, "#user-info", as: fn html ->
  %{user_html: html, has_user_info: html != ""}
end)
# context.assigns.user_html => "<div>..."
# context.assigns.has_user_info => true
```

## Resolvable Values

Most functions that accept an argument (selectors, URLs, values) also accept a 1-arity function. The function receives the current context, so you can build dynamic values from assigns:

```elixir
# Using a function to build a dynamic selector
click(context, &"#product-#{&1.assigns.product_id}")

# Using a function for a dynamic URL
navigate(context, &"#{&1.assigns.base_url}/products/#{&1.assigns.product_id}")

# Using a function for a dynamic fill value
fill(context, "#search", &"#{&1.assigns.search_term}")
```

This is particularly useful when data from a previous step or iteration drives what you do next.

## Halting and Errors

### Halting

`LiveLoad.Scenario.Context.halt/1` manually stops the pipeline and prevents further iterations for this user:

```elixir
def run(context, _user_id, _config) do
  context
  |> navigate("https://myapp.com/")
  |> wait_for_liveview()
  |> inner_text("#status", as: :status)
  |> maybe_halt()
end

defp maybe_halt(%{assigns: %{status: "maintenance"}} = context), do: halt(context)
defp maybe_halt(context), do: context
```

A halted context will not loop again! The user process immediately terminates and the user is marked as "succeeded".

You can check if a context is halted with the `LiveLoad.Scenario.Context.halted?/1` guard.

### Errors

Errors happen automatically when an operation fails (element not found, navigation timeout, etc.). They're captured on the context as a `LiveLoad.Scenario.Error` and prevent any further operations from running.

You can also manually mark a context as failed with `LiveLoad.Scenario.Context.fail/2`:

```elixir
def run(context, _user_id, _config) do
  context
  |> navigate("https://myapp.com/")
  |> wait_for_liveview()
  |> inner_text("#status", as: :status)
  |> check_status()
end

defp check_status(%{assigns: %{status: "error"}} = context), do: fail(context, :unexpected_error_status)
defp check_status(context), do: context
```

Halting and errors are mutually exclusive. This means that if an error has already occurred, calling `LiveLoad.Scenario.Context.halt/1` is a no-op. This is done to preserve the actual reason the scenario stopped. Similarly, if a context is already failed, calling `LiveLoad.Scenario.Context.fail/2` again is a no-op to preserve the original error.

A failed context, like a halted one, will not loop again. The user process will terminate and be marked as "failed".

## Throttles

Throttles are cluster-wide rate limiting mechanisms. They're useful when you want to control _how fast_ your simulated users perform actions, rather than just _how many_ users there are. The throttling is smoothed, so if you set a rate of 100 per minute, you get roughly one execution every 600ms, not 100 at the start of each minute.

Define throttles in the `c:LiveLoad.Scenario.throttles/1` callback and use them in `c:LiveLoad.Scenario.run/3` with `LiveLoad.Scenario.Context.throttle/2`:

```elixir
defmodule MyApp.LoadTest.CheckoutScenario do
  use LiveLoad.Scenario

  alias LiveLoad.Scenario.Throttle.Rate

  @impl true
  def throttles(_config) do
    [
      Rate.new(:checkouts, 10)
    ]
  end

  @impl true
  def run(context, _user_id, _config) do
    context
    |> throttle(:checkouts)
    |> navigate("https://myapp.com/checkout")
    |> wait_for_liveview()
    |> submit_form("#checkout-form")
  end
end
```

The `LiveLoad.Scenario.Context.throttle/2` call will block the user process until the throttle allows it through.

### Throttle Types

**`LiveLoad.Scenario.Throttle.Rate`**: limits the number of events per interval. The default interval is one minute.

```elixir
# 100 per minute (default interval)
Rate.new(:visitors, 100)

# 10 per second
Rate.new(:visitors, 10)
|> Rate.interval(to_timeout(second: 1))

# 500 per 30 seconds
Rate.new(:visitors, 500)
|> Rate.interval(to_timeout(second: 30))
```

**`LiveLoad.Scenario.Throttle.Interarrival`**: enforces a fixed amount of time between events.

```elixir
# One event every 500ms
Interarrival.new(:api_calls, to_timeout(millisecond: 500))

# One event every 2 seconds
Interarrival.new(:api_calls, to_timeout(second: 2))
```

**`LiveLoad.Scenario.Throttle.Parallelism`**: limits concurrent executions at any given time.

```elixir
# At most 5 concurrent checkouts
Parallelism.new(:checkouts, 5)
```

### Ramping Up

`LiveLoad.Scenario.Throttle.Rate` and `LiveLoad.Scenario.Throttle.Interarrival` throttles support gradual ramp-ups, so you can start slow and increase load over time.

```elixir
# Start at 10 per minute, ramp to 100 per minute over 5 minutes
Rate.new(:visitors, 10)
|> Rate.ramp(100, duration: to_timeout(minute: 5))

# Start at one event per second, ramp to 100 per second over 2 minutes
Interarrival.new(:api_calls, to_timeout(second: 1))
|> Interarrival.ramp(100, duration: to_timeout(minute: 2))
```

You can also define the ramp in terms of steps and intervals instead of a total duration:

```elixir
# Ramp from 10 to 100 in 10 steps, one step every 30 seconds
Rate.new(:visitors, 10)
|> Rate.ramp(100, steps: 10, interval: to_timeout(second: 30))
```

You can define multiple throttles on a single scenario and use them at different points in your pipeline:

```elixir
@impl true
def throttles(_config) do
  [
    Rate.new(:page_views, 100),
    Rate.new(:checkouts, 10),
  ]
end

@impl true
def run(context, _user_id, _config) do
  context
  |> throttle(:page_views)
  |> navigate("https://myapp.com/products")
  |> wait_for_liveview()
  |> click("#buy-now")
  |> throttle(:checkouts)
  |> submit_form("#checkout-form")
end
```

## Browser Context Storage

You can snapshot, restore, and reset the browser context's storage (cookies, local storage, session storage). This is useful when you want to save a logged-in session and restore it on the next iteration, or reset to a clean state.

```elixir
def run(context, user_id, _config) do
  context
  |> navigate("https://myapp.com/login")
  |> wait_for_liveview()
  |> fill("#email", &"user#{&1.assigns[:iteration] || user_id}@example.com")
  |> fill("#password", "password123")
  |> submit_form("#login-form")
  |> context_storage_snapshot(as: :session)
  |> assign(:iteration, (context.assigns[:iteration] || 0) + 1)
end
```

Then on a subsequent iteration, you could restore it:

```elixir
# Restore a previous session
restore_context_storage(context, & &1.assigns.session)

# Or wipe everything clean
reset_context_storage(context)
```

## Timeouts

Two timeout values control the execution:

- **`:scenario_duration`** (default: 10 minutes): how long the scenario loops for. Once this expires, the current iteration finishes and the user terminates.
- **`:iteration_timeout`** (default: 2 minutes): the maximum time for a single iteration of `c:LiveLoad.Scenario.run/3`. If your scenario doesn't complete within this window, the user process is killed and the failure is recorded.

Neither accepts `:infinity`. The timeouts must complete, a test must not run forever.

```elixir
LiveLoad.run(
  scenario: MyApp.LoadTest.SlowScenario,
  users: 5,
  scenario_duration: to_timeout(minute: 30),
  iteration_timeout: to_timeout(minute: 5)
)
```

## Scenario Discovery

You can tell LiveLoad which scenarios to run in three ways, in priority order:

1. **`:scenario`**: a single module.
2. **`:scenarios`**: a list of modules.
3. **`:otp_app`**: an OTP application. LiveLoad scans all compiled modules in the application for anything implementing the `LiveLoad.Scenario` behaviour.

```elixir
# Run one
LiveLoad.run(scenario: MyApp.LoadTest.HomepageScenario, users: 10)

# Run a few
LiveLoad.run(scenarios: [MyApp.LoadTest.HomepageScenario, MyApp.LoadTest.CheckoutScenario], users: 10)

# Run all scenarios in an app
LiveLoad.run(otp_app: :my_app, users: 10)
```

When multiple scenarios are discovered, they run sequentially, one at a time, in discovery order. **This is intentional**. Since all scenarios target the same application, running them sequentially ensures clean, isolated measurements. When running LiveLoad with the `distributed?` option set to true, each scenario will also run with a completely clean pool of nodes. This ensures that no carry-over of memory leaks, CPU usage, or data occurs between scenarios.

## Putting It All Together

Here's a more complete scenario that uses most of the features covered above:

```elixir
defmodule MyApp.LoadTest.ShoppingScenario do
  use LiveLoad.Scenario

  alias LiveLoad.Scenario.Throttle.Rate

  @impl true
  def config(opts) do
    {:ok, %{base_url: opts[:base_url] || "https://myapp.com"}}
  end

  @impl true
  def throttles(_config) do
    [
      :browsing |> Rate.new(50) |> Rate.ramp(200, duration: to_timeout(minute: 3)),
      Rate.new(:purchases, 10)
    ]
  end

  @impl true
  def run(context, user_id, config) do
    context
    |> reset_assigns()
    |> assign(:user_id, user_id)
    |> throttle(:browsing)
    |> navigate("#{config.base_url}/products")
    |> wait_for_liveview()
    |> inner_text("#product-count", as: :product_count)
    |> click("#featured-product")
    |> wait_for_phx_loading_completion(:click, "#featured-product")
    |> get_attribute("#product-detail", "data-product-id", as: :product_id)
    |> click("#add-to-cart")
    |> wait_for_phx_loading_completion(:click, "#add-to-cart")
    |> throttle(:purchases)
    |> navigate("#{config.base_url}/checkout")
    |> wait_for_liveview()
    |> fill("#email", &"user#{&1.assigns.user_id}@loadtest.com")
    |> submit_form("#checkout-form")
  end
end
```