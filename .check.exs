# SPDX-FileCopyrightText: 2024 splode contributors <https://github.com/ash-project/splode/graphs/contributors>
#
# SPDX-License-Identifier: MIT

[
  tools: [
    {:doctor, false},
    {:reuse, command: ["pipx", "run", "reuse", "lint", "-q"]}
  ]
]
