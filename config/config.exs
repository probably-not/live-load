import Config

config :git_hooks,
  auto_install: true,
  verbose: true,
  hooks: [
    post_checkout: [
      tasks: [
        {:mix_task, :"deps.get"},
        {:mix_task, :"deps.compile"}
      ]
    ],
    pre_commit: [
      tasks: [
        {:mix_task, :format, ["--check-formatted"]},
        {:mix_task, :credo}
      ]
    ],
    pre_push: [
      tasks: [
        {:mix_task, :test},
        {:mix_task, :"deps.unlock", ["--check-unused"]}
      ]
    ]
  ]

import_config "#{config_env()}.exs"
