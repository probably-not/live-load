# LiveLoad

![Elixir CI](https://github.com/probably-not/live-load/actions/workflows/pipeline.yaml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Hex version badge](https://img.shields.io/hexpm/v/live_load.svg)](https://hex.pm/packages/live_load)

<!-- README START -->

<!-- HEX PACKAGE DESCRIPTION START -->

A load testing framework for simulating real, distributed, live load on your application.

## DISCLAIMER:

The LiveLoad repo is currently private as I am building out the functionality and validating that it works as expected.

<!-- HEX PACKAGE DESCRIPTION END -->

If you come across this package and are installing it for some reason - just know that it's not public yet because I haven't actually tested it at all.
There might not even be any code in here yet - I literally just started the project and set up my CI/CD pipelines (it's a default thing I do when I start a project, I'm weird like that).
I will make it public (and update this description to remove this disclaimer) as I build and test it out.
Or - if it doesn't work out, I'll simply delete it.


## Installation

[LiveLoad is available on Hex](https://hex.pm/packages/live_load).

To install, add it to you dependencies in your project's `mix.exs`.

```elixir
def deps do
  [
    {:live_load, ">= 0.0.1"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/live_load>.

<!-- README END -->