# Devlog

So, I started out by writing my progress in the [Changelog](./CHANGELOG.md), and sort of updating the version and writing the changes there.
But then I realized - that doesn't make sense! I'm probably going to reset the Changelog the moment I actually make a real release...
so why am I writing everything there. Plus, I was basically writing a Devlog and just using the Changelog to write down progress and thoughts throughout.
So... welcome to the LiveLoad Devlog! Where I, [**@probably-not**](https://github.com/probably-not), will be describing my work as I go through it.

The Devlog is going to follow a similar structure to the Changelog. As I work and find "release-points" that make sense to me in some arbitrary way,
I'll cut a release, and update the Devlog. The Changelog is going to be fully reset, and basically irrelevant (until I actually make a real release).

# 0.0.1-rc.13

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
