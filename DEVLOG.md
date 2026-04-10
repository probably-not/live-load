# Devlog

So, I started out by writing my progress in the [Changelog](./CHANGELOG.md), and sort of updating the version and writing the changes there.
But then I realized - that doesn't make sense! I'm probably going to reset the Changelog the moment I actually make a real release...
so why am I writing everything there. Plus, I was basically writing a Devlog and just using the Changelog to write down progress and thoughts throughout.
So... welcome to the LiveLoad Devlog! Where I, [**@probably-not**](https://github.com/probably-not), will be describing my work as I go through it.

The Devlog is going to follow a similar structure to the Changelog. As I work and find "release-points" that make sense to me in some arbitrary way,
I'll cut a release, and update the Devlog. The Changelog is going to be fully reset, and basically irrelevant (until I actually make a real release).

## 0.0.1-rc.19

Alright, first pass at a topology has been completed! I kept this to specifically the topology of LiveLoad on the primary node, instead of LiveLoad runner nodes. Since the runner nodes are currently pretty closed off and don't have much of a topology (only the browser, the telemetry listener, and the task supervisor) and they get torn down when the primary process completes, I'll take care of that at a slightly later stage (or when I want to procrastinate a bit...).

For now, the topology is pretty cool (I think? Maybe not...):
- A `LiveLoad.Topology` supervisor, which starts up the underlying processes in a lazy initialization.
- A peer node linked GenServer for the Amoc peer node. This way I don't have to keep doing the `Application.stop` and `Application.ensure_all_started` calls every time. The peer node is isolated and it runs where necessary. Of course, this doesn't solve the whole locking thing... I did that by using the scenario name and a registry. So, everything is locked by scenario name, and the registry takes care of everything that handles uniqueness.
- A Supervisor that is prepared for the FLAME.Pool if necessary
- The Telemetry Collector which now has a lazy initialization of the cluster nodes that it is handling.

That is all put together under a Dynamic Supervisor, so I have a tree now! Maybe I'll have some LLM whip up a nice diagram that shows the topology itself at some point... that would be nice!

Ok, this was a short devlog entry, I'm really feeling it today, so I want to keep running and actually take some benchmarks by tonight. But I wanted to cut a release with all of these changes, since the library is actually close to a full usable state now!

Copying over the next up section from the previous entry to here, just so I can keep track of it (something about seeing the todos has been helping my ADHD keep track of them, strange, right?):

### Next Up TODOs

So, we're almost done with everything! Now it's a lot of busy work. Things are working and running, but I need to actually finalize the code and make it usable as a real library. Some of the list stays the same:
- Finish implementing all of the browser stuff (of course)
- The UI/Reporting (for pretty graphs!)
- Actual examples of a LiveView app and benchmarks (I'll need to set up a demo application and then run benchmarks against it)
- Clear the TODOs of the guides (so people can see examples and baselines) and polish the documentation of the `LiveLoad` module and the README.md

And then we have some less important but super cool ones that I would love to throw in:
- `:amoc_coordinator` implementation within a `LiveLoad.Scenario` to allow multiple users to coordinate together
- `:amoc_throttle` implementation within a `LiveLoad.Scenario` to allow user throttling, gradual increase, the works


## 0.0.1-rc.18

Wooooooooow! Ok, I'm just gonna get right to the updates here, because I'm feeling good, I'm in the zone, I'm finishing and finalizing and polishing this package to perfection.

Let's get some of the boring stuff out of the way first. It's a bit out of order, because I did these boring things last, but I want to just say them quickly so that I can get to the cool stuff that makes me overly inflate my ego because I feel awesome.

### The Boring Stuff

#### Upgrading Dependencies

A couple of hours ago, I ran `mix hex.outdated` and saw that I had a few outdated dependencies:
- `Credo`
- `Styler`
- `ExDoc`
- `:telemetry`

So I went ahead and just upgraded them all. I updated my `.credo.exs` to get the latest checks in, recreated my docs with `mix docs` to see what changed in ExDoc, and re-ran `mix format` to make sure all of the Styler changes were incorporated. Easy stuff. Boring stuff. But, it's necessary... gotta keep things up to date!

#### Fork `PlaywrightEx` Temporarily

I mentioned this in the [devlog entry for 0.0.1-rc.17](#0-0-1-rc-17), but since I opened up a couple of PRs for `PlaywrightEx` that require a breaking change for `LiveLoad`, I haven't been able to actually publish a real package that can be tested by others. Now, while that's not a *huge* deal... it is a problem as I move forward with `LiveLoad`. So, in order to publish and also properly test the package in other environments and as a real dependency, I went ahead and published the fork as the [`live_load_forked_playwright_ex`](https://hex.pm/packages/live_load_forked_playwright_ex) on Hex. It's just a temporary measure, I needed a quick solution there that would give me publishing for `LiveLoad` back. Once those two PRs are merged in to the real `PlaywrightEx`, I'll retire the fork and use the main package.

#### Clearing Out Various TODOs Left By Previous Work

One of the things that I always do as I write code is leave little TODO breadcrumbs all over the place. It's a helpful mechanism to me, it lets me put something to the side, and just keep running with what I currently want to run with, but have the breadcrumb left there so that I get back to it eventually. Well, today was that day! I went through and started clearing out various TODOs, mostly ones that were easy to just punch through. I spruced up the typespecs and typedoc blocks, I documented some modules and functions that I left undocumented, I simplified some things like removing the whole "passing options in the `use LiveLoad.Scenario` statement" (I honestly don't know why I thought that was a good idea, it overcomplicated things), I made a simple `:persistent_term` cache for the browser telemetry script that I inject to Playwright Browser Contexts, I created a debug listener for unknown Playwright messages received by the Metrics GenServer, I created the first issue in the repo (https://github.com/probably-not/live-load/issues/2) to remove a TODO that was not really bothering anyone (it's a "good first issue" labeled issue, so if you're reading this and I've open sourced the repo already, feel free to take a look and contribute!), I allowed `LiveLoad.Result.NodeResult` values to have a status so that reporters can report on node failures, and I finally reviewed the AI generated `LiveLoad.ResultTest` and cleaned it up!

Whew. That was a lot of TODOs cleared. What can I say... I felt good today! Now, on to the cool stuff!

### The Cool Stuff!!!

CLUSTERING BABY! Oh wait, I have a GIF for this (from another of my favorite quotable movies):

![Yeah baby yeah!](./assets/austin-powers-yeah-baby.gif)

Two days ago, after writing up the [devlog entry for 0.0.1-rc.17](#0-0-1-rc-17), I spent about an hour creating the `FlamePeer` package. I have a couple of other packages that helped me work through this pretty easily: [`FlameEC2`](https://github.com/probably-not/flame-ec2) and [`SafeNIF`](https://github.com/probably-not/safe-nif). Most of `FlamePeer` is a copy of both of these put together: the structure of how I built the `FLAME.Backend` was copied over (and cleaned) from `FlameEC2`, and the creation of a `:peer` node was copied over from `SafeNIF`. Having a `:peer` based backend to FLAME gave me the most important step in testing out `:amoc_dist`... an actual real distributed cluster!

From there, it was just a matter of putting together all of the steps to create a cluster, forcing it to scale up to the necessary number of nodes, and triggering `:amoc_cluster.connect_nodes/1` to connect to these new nodes! Aaaaaand... voila! We've got clustering!

#### How Does Clustering Actually Work?

I'm glad you asked, random reader! Let me tell you.

Everything happens within the `LiveLoad.Cluster.start_link/5` function. Now, this `start_link`, like a few other `start_link`s sprinkled throughout this codebase, is not a proper `start_link` function. That's another TODO for me (it's the next one up actually), I need to go through and get to packaging and finalizing the whole thing into a real supervision tree, and return resources from initialization functions and everything.

The first thing that happens is pool creation. `LiveLoad.Cluster` sets up a `FLAME.Pool` with the given `FLAME.Backend` (this is why I needed `FlamePeer`, to actually have a real cluster to test against). The pool is initialized with a minimum count of 0, a maximum count of the configured maximum allowed nodes (defaults to 100), a maximum concurrency of 1, and resource tracking set to `true`. Then, I use `FLAME.call` initialize a `LiveLoad.Cluster.Node`, which implements `FLAME.Trackable` to ensure that FLAME tracks it after the `FLAME.call` returns. The `LiveLoad.Cluster.Node` contains all of the necessary details that I need to determine the necessary cluster size and whether the resources available in combination with the maximum allowed nodes can actually handle this load test! I added a couple of callbacks to the `LiveLoad.Browser.Connection` behaviour, specifically to identify the potential resource usage of each browser and browser context. Based on the potential resource usage per browser and browser context, I wrote up a simple (very conservative) heuristic for determining the number of users that can be added to each node, and then used that to start up all of the other nodes! And boom! We have a cluster. Each started node in the cluster contains the Trackable `LiveLoad.Cluster.Node`, so it stays alive as long as that process exists on the node (forever, since I'm not actually killing that process anywhere).

#### That's Awesome Coby, Now What?

So, once we have clustering, I had to make a few changes, specifically to the telemetry collection. Until now, I wasn't actually monitoring the expected nodes in the `LiveLoad.Telemetry.Collector`, so it ended up in a situation where if a node died (like from an OOM for example), it would wait forever because that node would never report completion. So I made sure that the nodes are all monitored by the collector, and set the stats to an error value whenever a node goes down.

Wow... Amazing!

### Next Up TODOs

So, we're almost done with everything! Now it's a lot of busy work. Things are working and running, but I need to actually finalize the code and make it usable as a real library. Some of the list stays the same:
- Finish implementing all of the browser stuff (of course)
- The UI/Reporting (for pretty graphs!)
- Actual examples of a LiveView app and benchmarks (I'll need to set up a demo application and then run benchmarks against it)
- Clear the TODOs of the guides (so people can see examples and baselines) and polish the documentation of the `LiveLoad` module and the README.md

But we have another couple of cool ones to add to the list (which is what I'm actually going to work on next):
- Topology and Supervision Trees. Until now, I've sort of been brute-forcing a lot of stuff and using the function name `start_link` for a lot of stuff that's not a real `start_link`. Now, nothing is not linked (that's a huge no in my opinion) but I don't have any proper topology. My idea here is to create a lot of lazy initialization processes and set up a topology supervisor. Each runner node is going to need a topology started up on it (the browser, the telemetry listener, the partitioned task supervisor for the scenario runner), and the main runner node will need a topology for the actual scenario run (the telemetry collector, the cluster, and amoc's controller which I may need to encapsulate into a peer node).
- In addition to topology, I have a couple of global locks that I need to implement. For one thing, FLAME and `:amoc` both have global state: FLAME's pool names must be atoms (since metadata is stored in named ETS tables) and `:amoc` is just all global state (that's why you can see that I do a lot of `Application.stop(:amoc)`, `Application.ensure_all_started(:amoc)` everywhere). I could handle this by using `:peer` nodes here (wow, I'm starting to really like `:peer` nodes...), but I can't spin up infinite nodes. So I'm probably going to need to implement some sort of queuing mechanism, maybe based on a target? Scenario's to the same target should run one at a time, so maybe a queue per target, and an overall queue so that if I have spun up too many `:peer` nodes I force the caller to wait until the next thing? This one is less important for a first public release, since it could be defined as a limitation of the library initially, but I'm adding it to my list of things I want to do.

And then we have some less important but super cool ones that I would love to throw in:
- `:amoc_coordinator` implementation within a `LiveLoad.Scenario` to allow multiple users to coordinate together
- `:amoc_throttle` implementation within a `LiveLoad.Scenario` to allow user throttling, gradual increase, the works

OK WOW THAT WAS SO MUCH. That's all I've got though! You'll have to wait for my next "in the zone" time for an update!

## 0.0.1-rc.17

Am I procrastinating? You bet I am! But hey, it happens to the best of us.

This release is a quick (ish) procrastination release. It contains a bunch of stuff that I saw and that my ADHD brain said "hey, this will be easy, just fix this one thing before going on to others."

So, here's what I've done:

### Proper Playwright Installation

So far, I've been "vendoring" Playwright in LiveLoad's `priv` folder. Now, I say "vendoring" in quotes, because I've basically just been keeping a TAR archive of the current Playwright installation there, with a simple Mix Task that would initialize Playwright for me based on stuff that I have hidden in my `assets` directory (gitignored and not pushed to the repo). While this worked for now, it wasn't going to fly when it comes to actually installing `LiveLoad`... for many reasons, chief among them being that Playwright is not a universal cross-platform binary, it needs to be installed per platform! So I went ahead and set up an actual installation process. Running [`mix live_load.install`](`Mix.Tasks.LiveLoad.Install`) will install the default version of Playwright (currently at time of writing it's 1.59.1) into the `priv` directory of the `LiveLoad` installation, then compress it up so that it's ready to be pushed with the release.

Through this process, I also found a couple of issues that need fixing in the `PlaywrightEx` library:
- Most important is [ftes/playwright_ex#34](https://github.com/ftes/playwright_ex/pull/34), which adds the `:env` option to `PlaywrightEx.PortTransport`. This is extremely important, since it allows us to actually vendor the browsers (i.e. not requiring the install live in the app). This actually causes a breaking change in `LiveLoad` since I added the browser cache directory in the environment options. I know that [Fredrik](https://github.com/ftes) is very active on `PlaywrightEx`, so hopefully this will go in pretty quickly and get released. But if it doesn't, in order to push `LiveLoad` publicly I'll probably make a "live_load_forked_playwright_ex" package on Hex just to make sure I don't get blocked there.
- Once I pushed that, I added in [ftes/playwright_ex#35](https://github.com/ftes/playwright_ex/pull/35), which adds a couple of convenience functions for `LiveLoad`. Since Playwright version 1.59 (and the whole reason why this procrastination happened) there's a way to force clear all of the storage details that a browser context has without recreating the context. So I added these convenience functions within `PlaywrightEx.BrowserContext` to let me call them instead of calling `Playwright.Connection.send/3` directly. This however, is not breaking... I can just call `Playwright.Connection.send/3` directly for now. But, procrastination wins, so I still made this PR!

### Enabling the User Loop

Load tests are not just "one and done" (usually). And I've been modeling my `LiveLoad.Scenario` as one and done. The person who is using `LiveLoad` doesn't need to necessarily concern themselves with creating a loop or a process for their `LiveLoad.Scenario`. `LiveLoad` does this for them, all they need to do is write a declarative scenario: "navigate here -> click here -> wait for this -> submit this". `LiveLoad` takes care of everything. But until now, my `LiveLoad.Scenario.Runner` process (a `:gen_statem`, which as some of you might know is my favorite OTP behaviour) has just been running it as a one and done. Well... not anymore! I added the looping mechanism, which also led to a bunch of cleanups in how I was passing options, and naming options, and more. This also led me to actually implementing checks on the `LiveLoad.Scenario.Context`, to make sure that a failure actually counted as a failure! A huge (not really, but it was an important one) milestone!

Now, because of that first point about the Playwright `:env` option, this release is not going to be usable. So, anyone who is using it (I don't know, there's downloads on Hex, so I'm warning you here) this is going to break your current workflows. Locally, I'm pointing to a local path on my own fork of `PlaywrightEx`(https://github.com/probably-not/playwright_ex) so that it can work, but like I said, for now, it's a broken push. I just wanted to push it up, so that if for some reason people are following this devlog, they'll see what I'm doing.

So, since this was a procrastination release, our next todos haven't changed. I'm just going to copy it from the last entry that had them so I can remind myself as well:
- Finish implementing all of the browser stuff. The busy work that I've been mentioning this whole time. I gotta do it.
- Distribution. I'm gonna need to set up FLAME peer nodes so I can actually finish this stuff.
- The UI/Reporting. I was discussing this with one of my colleagues - I'm not sure if I should go with just a basic Plug and a vanilla frontend that I get Claude to generate, or if I should go all the way and make this in LiveView already. I could set up an Igniter script to let people install the reporting UI on their own LiveView projects. The benefit of a basic Plug is that it's standalone - I could place it in any app, whether it's Phoenix, Phoenix+LiveView, or anything else in the BEAM ecosystem via interop even. So LiveLoad, while being primarily oriented around LiveView metrics, could theoretically be used to load test any app, which would be a huge thing!
- Actual examples of a LiveView app and benchmarks
- And last but not least, finish up the documentation. The guides, the todos for docs, all that fun stuff.

## 0.0.1-rc.16

![Oh, that little guy? I wouldn't worry about that little guy.](./assets/supertroopers-little-guy.gif)

> Oh, this little release? I wouldn't worry about this little release.

Super Troopers is one of my all time favorite movies, purely for its "quotability". One of my best friends and I even came up with a game that we call "Quotations!" - a card game that has a few different type of "quote cards", and you have to give the details that the card requests. We love quoting random movies and TV shows, and Super Troopers is absolutely at the top of the list!

Anyways, enough of a prelude as to why I am adding Super Troopers GIFs. This isn't just a little release! I'm just feeling good and the quote came into my head... in reality, this release is pretty big! See, after the last release where I wrapped up the full metrics pipeline (or so I thought), I actually started trying to analyze the metrics. And at first glance, they seemed pretty easy to analyze. Classic histograms, being able to see what took a long time, that sort of thing. But then I realized... none of the metrics were really all that helpful? See, I fell into this trap of saying "oh, a histogram, good, I know how those work from Grafana" and I sort of just equated having percentiles to being able to say what happened, but in the real world of benchmarking and incidents and all that fun stuff, you gotta have TIME! I was missing an entire dimension that would allow a user to use `LiveLoad.run/1` and be able to see when things broke down.

So this release is all about time. I went through all of the metrics being collected (counters and histograms) and I refactored the `LiveLoad.Telemetry.Listener` to receive telemetry and map it to a time bucket. Then, I split up my result functionality. I moved the original result struct that was in `LiveLoad.Result` into `LiveLoad.Telemetry.Result`, and created a brand new `LiveLoad.Result` struct which receives all of the results and compiles it into a single, compact, serializable final result. It's not really optimized... I had to do a bunch of loops on loops and the final structure is... pretty exploded.

When I tested everything by running

```elixir
result = LiveLoad.run(users: 10)
:erts_debug.size(result)
File.write!("./result.example.json", JSON.encode!(result))
```

for my `LiveLoad.Scenario.Example` this ended up exploding into a 30KB structure. If I changed the bucket size to be smaller than the default 5 second, it explodes EVEN MORE. But you know what? This part doesn't really need to be optimal. I wanted to create a structure that I can through at any reporting tool without needing to know the underlying mechanics of how `LiveLoad` actually collects and measures the telemetry. This way I can just create a self-contained reporting mechanism that assumes this data structure and just outputs a nice visual report. No need for an embedded mechanism, or knowing how exactly the sketches and quantiles are measured. Everything is precomputed and serialized in the end.

Of course, after I wrote that monster of a merging function, it was way too late in the day, so I became the thing I hate - a person who throws a module at an LLM and tells it to "write me comprehensive tests for this module make no mistakes" and then trusts those tests blindly. I'm going to really need to dive into those tests and probably rewrite them at some point... I have no clue if they even do anything. But it was midnight, I'd been working on my dayjob since 7:30 in the morning, and I just wanted some sort of basic security in my brain that would let me say "yes, not only did you write a massive complicated merging function, but now it's totally tested... you're awesome".

Anyways - that's what this release is about. We've got all the metrics - time series, global, per node, precomputed quantiles, dimensioned histograms and counters, the works.

Let's get on to distribution!

## 0.0.1-rc.15

I did a big update of a bunch of stuff yesterday, so today is just sort of, the wrapping up of this whole week of metrics! I spent the day connecting everything from the last week up to the internal LiveLoad telemetry pipeline, and lo and behold, I've got metrics for scenarios! It's pretty cool, I can see a ton of data, and while I've only been testing it with a simple Markdown exporter and the demo scenario and 10 users (because everything is local on my own laptop) but it's giving histograms, percentiles, counts, and so many fun things!

For anyone who wants to play around a little bit, pull down the project, and run this:

```elixir
LiveLoad.run(users: 10) |> tap(&LiveLoad.Reporter.Markdown.write!/1)
```

You'll see a markdown file appear with a bunch of output that shows the metrics collected! It's pinging my dayjob's app homepage, so there is not really anything there, but it looks good.

I also started adding in some Agentic coding sessions in this release and the last one as well. I put up disclaimers wherever I do... I think people should be really upfront about when they are using AI, so I'm following through by giving my methodology wherever I do. In this case, it's in the browser telemetry JavaScript file, and the Markdown reporter (I just didn't want to try and figure out the markdown stuff on my own). I'll probably also use Claude (my prefered LLM) for figuring out a real UI for the reporting. I don't use Claude Code or any agents in the codebase (I'm a purist, what can I say) but I've used Claude on the web to do plenty of UI stuff. I'm color blind, so I don't really like doing UI... but Claude seems good enough at that, so for people wanting to see pretty graphs after a load test, I'll see whether I can get Claude to generate some cool graphs and a fun reporting mechanism.

Thinking about it now, I may want to add an AI Policy somewhere to the repo... I know other open source projects have added policies about using AI. My view is that any code contributed needs to be validated by a human and the human has to know what they're actually talking about. So maybe I'll adopt an AI Policy and place it in the repo so that when I open source it, people will follow it. I don't know... I'm not open sourcing yet, so I've got time to figure that part out.

So, let's summarize what's next:
- Finish implementing all of the browser stuff. The busy work that I've been mentioning this whole time. I gotta do it.
- Distribution. I'm gonna need to set up FLAME peer nodes so I can actually finish this stuff.
- The UI/Reporting. I was discussing this with one of my colleagues - I'm not sure if I should go with just a basic Plug and a vanilla frontend that I get Claude to generate, or if I should go all the way and make this in LiveView already. I could set up an Igniter script to let people install the reporting UI on their own LiveView projects. The benefit of a basic Plug is that it's standalone - I could place it in any app, whether it's Phoenix, Phoenix+LiveView, or anything else in the BEAM ecosystem via interop even. So LiveLoad, while being primarily oriented around LiveView metrics, could theoretically be used to load test any app, which would be a huge thing!
- Actual examples of a LiveView app and benchmarks
- And last but not least, finish up the documentation. The guides, the todos for docs, all that fun stuff.

## 0.0.1-rc.14

God damn I'm good. I mean, I'm an engineer... I obviously have a huge ego. But I just feel great after a week of sprinting a bunch on all the metrics stuff. So screw it! Ego wins! I'm amazing!

Where to begin? Well, this week was all about metrics, or, more specifically, metrics emission (and a PoC of metrics collection to be expanded on next). Load tests are nothing without metrics, see, without metrics, how do you know what your app is actually behaving like under load? [In my 0.0.1-rc.12 push from a few days ago](#0-0-1-rc-12), I set up a small PoC for the metrics collection. I added the `LiveLoad.Telemetry.Listener` and the `LiveLoad.Telemetry.Collector`, which are the two necessary parts of the collection itself. The listener sits on the load testing node and collects the telemetry from that node, managing the DDSketches ([which I added in the 0.0.1-rc.13 push](#0-0-1-rc-13)) for that node, and when it finally detects the completion of all of the user processes on that node, it packages a final result and forwards it to the collector, which sits on the master node. In those pushes, I pushed everything as a PoC, using the built in metrics that are fired by [`:amoc`](`:amoc`). But now, I've gone into the next step: browser side metrics collection.

What's that Coby? Well, I'm glad you asked dear reader! See, [while `:amoc` can give us basic metrics around the user processes in the load test](https://hexdocs.pm/amoc/telemetry.html), it can't actually delve into the metrics behind Playwright, or the metrics behind what your LiveView app is actually doing. But you know who can? `LiveLoad`!

So, let's talk about the how:

First thing's first: `PlaywrightEx` is a wonderful library. [Fredrik](https://github.com/ftes) has done some amazing work there with regards to setting up the Playwright Connection, the communication protocol, and most importantly, the protocol subscription mechanism. See, Playwright pushes a lot of events on its protocol - most specifically, it pushes events around WebSockets and HTTP Requests/Responses. With `PlaywrightEx.subscribe/2` and `PlaywrightEx.Page.update_subscription/2`, I can subscribe to all of these events on a page, and on the individual created objects. So, when my subscription to a page receives a "WebSocket Created" event, I can immediately subscribe to that websocket's guid and receive the raw frames sent and received on that websocket! How's that for a huge metric? Does anyone track how big their LiveView diffs are? Well you can now!

Now, for the even deeper browser telemetry integration: HTTP Requests and the WebSocket frame sizes is one thing... but what if I told you I can track THE ACTUAL TIME IT TAKES FOR LIVEVIEW TO UPDATE THE DOM. See, LiveView uses a lot of DOM patching, especially for events handling. [There is a public set of classes listed in the Syncing Changes and Optimistic UIs Guide](https://hexdocs.pm/phoenix_live_view/syncing-changes.html#optimistic-uis-via-loading-classes) which are set and removed by LiveView whenever different events happen, which allows the LiveView developers to target these classes via CSS or JavaScript and use them to optimistically update the UI. These classes give a lot of insight to `LiveLoad` on the load testing side: we can figure out what load the server can handle based on how quickly these classes are added and removed, and not only that, we can measure how much load the LiveView frontend JavaScript code can handle in terms of the amount of complexity on the browser! So, we can do things like stress test not only from a massive amount of users side, but also from a massive amount of JS/CSS/events/hooks/etc side per user.

Now, I still haven't connected any of these browser metrics to the `LiveLoad.Telemetry.Listener` - I need to decide how I want to structure all of the DDSketches for everything. That will be done probably tomorrow - a good thing to get to for an end of week goal.

So, in summary (just like last release), here's what's next up:
- Connect all of the new telemetry to the `LiveLoad` telemetry pipeline so we can actually process it. This is one of the big milestones (the other being distribution).
- Finish implementing all of the browser stuff. Just like I mentioned in the last release, I've got the basic structure, I just need to do the "busy work" of going through and implementing it
- Distribution (the next big milestone that's critical)
- Like I mentioned in the last release - some sort of UI/Report for the sketches. I gotta actually show and analyze it
- And, finally... drumroll please... ACTUALLY RUNNING LOAD TESTS ON SOME SAMPLE APPS. I added a couple of empty guides for LiveLoad (with TODOs of course, I'm not a monster), and I think a good thing to do would be to have some baselines for Phoenix in order to actually showcase different situations and try to stretch it to the limit. I should come up with some scenarios that are good to test and find the limits of... probably stuff around live components, streams, JS hooks, things like that.

Whew. Okay! That was a lot! Now, a couple of housekeeping things occured between the last release and this one:
- I made some fixes to some stupid mistakes in my Markdown (that was [here](https://github.com/probably-not/live-load/commit/080d81f34c3c9146599274e8d078736c89e038aa))
- I cleaned up the [`mix.exs`](./mix.exs) file a bit to make the docs a bit better looking with sections and the like (that was [here](https://github.com/probably-not/live-load/commit/f7afb2c4b2c011afc8569a253c490dd055bf1f6b) and [here](https://github.com/probably-not/live-load/commit/c06d533955e3e87b8f61e8fcafc9d413e4fd5737)). That also fixed a previous mistake that I had made, I forgot that I needed to include the [`priv`](./priv/) directory in my files since I was putting the bundled Playwright into it.

The ball is rolling up!

## 0.0.1-rc.13

We've got basic metrics! Well... one metric... but it's a start!

Thanks to [Nelson's](https://github.com/NelsonVides) fantastic [ddskerl](https://github.com/NelsonVides/ddskerl) library, I got a very basic distributed/mergeable [DDSketch](https://arxiv.org/pdf/1908.10693) based metrics system. Since we are running in a distributed cluster, I went with DDSketch for the whole mergeability aspect. During the initialization (at the same point where we run the `c:LiveLoad.Scenario.config/1` callback) we set up our `LiveLoad.Browser` instance for the node, and additionally set up our `LiveLoad.Telemetry.Listener` (I should probably put both of these under a "Scenario.Supervisor" so that it just starts up everything...). This setup of the listener happened in [v0.0.1-rc.12](#0-0-1-rc-12), but now we've added in actual sketch handling. For now, it's just a simple collection of the scenario duration, but next up is setting up all of the metrics that we want to collect (loading durations for events, connect/disconnect durations, websocket diff sizes, etc).

That'll hopefully be the next release - pushing out a full metrics collection system from the frontend view. I was also thinking about seeing if I could figure out a clean way to collect metrics from the backend... LiveLoad is basically "blackbox" style testing, it doesn't know anything about the server side of things and doesn't collect metrics from there, it only collects metrics from the point of view of the user. But if I could also figure out a way to collect metrics from the server, I could have a single place where I see all of the metrics. Taking it even further, I would potentially be able to correlate things like spikes in latency with tracing of which functions actually spike (flame graphs galore). But... that's a future Coby problem. For now, I'll focus on the load testing from the outside aspect of things.

So, to summarize, the next stuff up:
- Full metrics collection of [everything](https://tenor.com/nZ6b.gif) (a semi appropriate meme... I know he says "everyone" but come on I gotta be a little dramatic and fun)
- Finish implementing all of the browser stuff. I have the connection, the context, the connection between the context and the operations, but I actually need to implement all of the operations (click, fill, focus, etc)
- Distribution implementation (obviously). I have a bunch of placeholders since I'm building this locally, but I'll need to set up FLAME with peer nodes and get the distribution set up at some point (like, soon)
- UI? Reports? Something? I gotta display the sketches somehow..

## 0.0.1-rc.12

Yes, we're so back! Ok, let's just dive right into it. Quite a few things have been pushed here today:
- Upgrading [`:amoc`](`:amoc`) to the latest version! They released their latest version, which now let me remove a ton of the TODOs and hacks around things like incorrect types. With this, I also went through and checked the old dialyzer ignore comments - and I saw that `PlaywrightEx` also solved some of their type issues. Huge props!
- Telemetry pipeline: This was what I needed to replace my misused usage of the [`:amoc_coordinator`](`:amoc_coordinator`). Each node has a telemetry listener, and the master node has a telemetry collector. It's all currently just "infra", no actual implementation of telemetry, but it's properly notifying when the user processes complete running on a node. The coordinator usage was removed... I'll bring it back later on in a proper way, allowing people to write scenarios that are correctly coordinating between multiple users.
- Scenario Discovery! I finally got around to implementing a super basic discovery mechanism for scenarios in a project. I set up the same type of thing as Ecto and Phoenix, using an `:otp_app` option. I also added some "inference" - making guesses on what the OTP app is without the user needing to specify, and allowed overrides at the config and option level, along with specifying exact specific scenarios to run if you don't want to run them all.

Good work this round, and I'm going to keep the momentum going next round with all of the necessary stuff around actual metrics. Gotta actually tell the developers what the data shows - how much overhead things add, what the performance is, etc. After that, it's on to the FLAME integration and distribution itself, which hopefully should be extremely fast and easy since most of the overhead is just handling spinning up the pool. Although of course... who knows? This is really fun!

## 0.0.1-rc.11

![Aaaaand we're back](./assets/abed.gif)

Aaaaand we're back. It's been about 5 weeks ish since my last touch on this project. Well, sort of. I made some plans and spoke with people, and learned a bunch more than I knew before about AMoC. But I didn't actually put in much work other than just adding the `browserContext.addInitScript` and `page.addInitScript` functionality to `PlaywrightEx` ([see the PR here](https://github.com/ftes/playwright_ex/pull/23)). I spent the last 5 weeks on a semi-vacation with my family, and although I did put in work in my day job, I mostly focused on closing that stuff and then spending time with my family, instead of working on `LiveLoad`... to be honest, I should have been working on this though. ElixirConf EU is coming up in about 6 weeks and I still need to write an entire metrics pipeline and then run benchmarks!! So I'm going to get on this now - hard mode activated.

For this update, it's just the upgrade to `PlaywrightEx` 0.5.0, so that I can prepare to write the browser level metrics. PlaywrightEx updated their internal architecture to allow adding a named connection, which lets me now scope the Playwright connection to LiveLoad, which solves a lot of compatibility issues - if I were to use this in a project that contained PlaywrightEx already, it would crash because of the process name being already started.

Next up, I'll put in work on the telemetry pipelines. I also ended up speaking with [Nelson](https://github.com/NelsonVides) and [Denys](https://github.com/DenysGonchar), two of the core maintainers of AMoC, and they helped me understand a lot of the quirks that I ran into with AMoC. One huge thing is that I'm definitely misusing the [`:amoc_coordinator`](`:amoc_coordinator`), but with what it can be used for, it's a huge powerful functionality. So first, I will add in a basic telemetry pipeline for collecting telemetry from each node on the master node, and in conjunction with that, I'll replace my current implementation of completion signaling with the [`:amoc_coordinator`](`:amoc_coordinator`) with a lightweight telemetry-based mechanism. And after that, I'll work on adding on a true coordinator mechanism that properly adds [`:amoc_coordinator`](`:amoc_coordinator`) functionality to coordinate actions between users.

## 0.0.1-rc.10

Yikes! I just realized I fully forgot to write up one of these last week... I've been trying to write one of these every week when I work on LiveLoad, and I did put in a bunch of work last Friday. What did I do? Let me try to remember. Ok well first off, I did upgrade all of the packages to get all of the new goodies. Specifically in ExDoc, so whoever is reading this right now for any reason, enjoy the new LLM/Markdown features of ExDoc! But on to the interesting things: `LiveLoad.Scenario.Context`. In 0.0.1-rc.9, I created the `LiveLoad.Scenario.Context` module and started by adding `LiveLoad.Scenario.Context.assign/3` and deciding to model it on `Plug.Conn`, so that people can build a pipeline inside a scenario and not have to worry about halting and errors and the like. Well, I've built it out a lot more! Since it's mostly mirroring the `LiveLoad.Browser.Context` modules, so I actually extracted the delegation into a helper function which is delegated to by all of the public API functions. This way, I can decide what calls what, and still document each individual function properly. I probably could have done something with a macro there... but who needs macros when you can have good old fashioned functions. Maybe for efficiency I'll add a compile flag for inlining the run function, that would essentially have it behave like a macro! Once I had the context in place, I actually created a real working scenario! It looks like this:

```elixir
defmodule LiveLoad.Scenario.Example do
  @moduledoc false
  use LiveLoad.Scenario

  @impl true
  def config(opts) do
    {:ok, Map.new(opts)}
  end

  @impl true
  def run(%LiveLoad.Scenario.Context{} = context, user_id, _config) do
    context
    |> navigate("https://app.marketeam.ai")
    |> ensure_liveview()
    |> wait_for_liveview()
    |> page_content()
    |> inner_html("body", as: :body)
    |> inner_html("a", as: fn _ -> :a end)
    |> inner_html("div", as: fn _ -> %{div: "a", div2: "b"} end)
    # credo:disable-for-next-line
    |> tap(fn context -> dbg({user_id, context}) end)

    :ok
  end
end
```

The `dbg/1` is in there as a check to make sure things are working. From the example, you can see I'm testing it on the app at MarkeTeam.ai (my day job). I navigate, ensure the liveview, wait for it to connect, get the content (without assigning it), and get the inner html of various selectors (while assigning in a couple of different ways to validate that part of the functionality).

Shockingly, it works! So once I throw together all of the functions that I actually need on the `LiveLoad.Browser.Context` and mirror them to the `LiveLoad.Scenario.Context` (things like click, fill, clear, basically everything from Playwright), I'll have a fully working library for running scenarios. Then it'll be on to metrics collection and distributing with AMoC and FLAME.

## 0.0.1-rc.9

Well well well, welcome aboard, Expert LSP! I've finally gotten around to setting up Expert on my local VSCode, connecting it up to the Lexical VSCode extention.
That means I could finally upgrade my setup from 1.18 to 1.19, which has been on my todo-list this whole time, since I started building LiveLoad.
So, from now on, I'll be pushing out with the latest and greatest for Elixir versions - right on time for me to start testing out the 1.20 release candidates
which are bringing even more strict-typing goodies into the language!

But now that this is out of the way, there's been a few other updates that I've done since the last update. Usually I try to work on this once a week and update
the Devlog so that I can track my own progress. But last week, I was featured on the [Elixir Mentor Podcast](https://www.youtube.com/watch?v=l9E0Jkhc7fw) where
I talked at length about what we do at my day job, so I didn't really have time to get down and dirty with LiveLoad. So what has happpened since then? Well, since
I didn't have much time, I did some experimenting with Playwright, focused on some cleanups, and most importantly, started building out the `LiveLoad.Scenario.Context`
module. This module is going to be the core struct passed around the `LiveLoad.Scenario`. I decided to model it in sort of the same way as a `Plug.Conn`, which is passed
through a Plug pipeline and allows plugs to update it and manipulate it, but also handles things like making everything a No-Op when it is halted. So when writing a scenario,
the user would be able to just call the functions on the `LiveLoad.Scenario.Context` struct, and these would mark things on the context struct. This is the second part of
LiveLoad that I've modeled on `Plug.Conn`... I added `LiveLoad.Browser.put_private/3` and `LiveLoad.Browser.Context.put_private/3` in the same way. Seems like Plug has some
good patterns to follow. Huh, who knew? Just kidding of course we all knew! Come on, it's basically a core library at this point.

## 0.0.1-rc.8

Take 2 of "A Devlog? Whaaaaat???"

## 0.0.1-rc.7

A Devlog? Whaaaaat???

Also, a quick change in the `LiveLoad.Browser.Connection` behaviour - instead of it requiring `start_link` as a callback,
I am requiring `child_spec` as a callback. This way, things that have global processes can simply use the default `child_spec`
implementation which returns `:ignore` in the supervision tree. I stole this pattern from the
[`Phoenix.PubSub.Adapter`](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.Adapter.html) behaviour.

## 0.0.1-rc.6

Alright, more things shaping up! For anyone who for some reason has pulled this library in and is looking at the documentation,
you will start to see that I have been making a lot of updates. First, the LiveLoad.Scenario module and it's functionality is fairly closed.
Obviusly there's still a lot of work to do here, but the overall runner functionality is working and solid - configs, amoc, timeouts, some tricks.
I did a lot more experimentation to try and understand amoc as well - so running should be pretty easy from now. I think next up I'll get back to
fleshing out the browser and making sure that scenarios have access to them and that they can use them. Should I make scenarios effect based? That
may make testing a bit simpler... I haven't thought about testing yet (it's usually the last thing I think about)...

## 0.0.1-rc.5

I've done a bunch of experimentation since the last release.
This code is still pretty much unusable...
But I figured, if there's anyone who has installed it for some reason, here's some progress that I've made.
You can see how this is shaping up, and take a look at my comments and todos throughout the code.
I'm still not going to really put anything into the Changelog yet - I'll probably strip the changelog when I actually release later on.

## 0.0.1-rc.4

Well, I screwed that one up... so let's try one more but with a shortend package description.

## 0.0.1-rc.3

Just one last one before I am ready to get started. Just wanted to get the README and the disclaimer out there.

## 0.0.1-rc.2

Still no code, but I realized that my version and my changelog are out of sync. This is why I need to figure out a way to automate this...

From now, we should be done and ready to go.

## 0.0.1-rc.1

Like I said on the rc.0, this is just a base release. No changes, other than the fact that I got the CI/CD workflow working.

There's literally no code written yet.

## 0.0.1-rc.0

This is a base release, to set up the repository, the project, initial workflows, and more.
There's probably going to be a couple of these as I just set up all of the necessary stuff and make sure my initial CI/CD workflows work.
