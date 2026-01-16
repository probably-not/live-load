# Devlog

So, I started out by writing my progress in the [Changelog](./CHANGELOG.md), and sort of updating the version and writing the changes there.
But then I realized - that doesn't make sense! I'm probably going to reset the Changelog the moment I actually make a real release...
so why am I writing everything there. Plus, I was basically writing a Devlog and just using the Changelog to write down progress and thoughts throughout.
So... welcome to the LiveLoad Devlog! Where I, [**@probably-not**](https://github.com/probably-not), will be describing my work as I go through it.

The Devlog is going to follow a similar structure to the Changelog. As I work and find "release-points" that make sense to me in some arbitrary way,
I'll cut a release, and update the Devlog. The Changelog is going to be fully reset, and basically irrelevant (until I actually make a real release).

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
(`Phoenix.PubSub.Adapter`)[https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.Adapter.html] behaviour.

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
