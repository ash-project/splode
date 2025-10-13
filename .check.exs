# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

[
  tools: [
    {:doctor, false},
    {:reuse, command: ["pipx", "run", "reuse", "lint", "-q"]}
  ]
]
