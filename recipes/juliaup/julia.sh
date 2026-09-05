#!/usr/bin/env bash
# Launches julia from the {{APP_NAME}} distribution.
#
# Install a channel first with `{{APP_NAME}}-juliaup add {{JULIAUP_CHANNEL}}`.

command -v julia >/dev/null || {
  echo "{{APP_NAME}}-julia: julia is not installed or not on the PATH. Install it using juliaup, see https://github.com/JuliaLang/juliaup" >&2
  exit 127
}

export JULIAUP_SERVER={{{JULIAUP_SERVER}}}
export JULIAUP_DEPOT_PATH="${HOME}/.julia/juliaup-depots/{{JULIAUP_DEPOT}}"

exec julia "$@"
