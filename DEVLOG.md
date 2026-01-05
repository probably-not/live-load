# Devlog

So, I started out by writing my progress in the [Changelog](./CHANGELOG.md), and sort of updating the version and writing the changes there.
But then I realized - that doesn't make sense! I'm probably going to reset the Changelog the moment I actually make a real release...
so why am I writing everything there. Plus, I was basically writing a Devlog and just using the Changelog to write down progress and thoughts throughout.
So... welcome to the LiveLoad Devlog! Where I, [**@probably-not**](https://github.com/probably-not), will be describing my work as I go through it.

The Devlog is going to follow a similar structure to the Changelog. As I work and find "release-points" that make sense to me in some arbitrary way,
I'll cut a release, and update the Devlog. The Changelog is going to be fully reset, and basically irrelevant (until I actually make a real release).

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
