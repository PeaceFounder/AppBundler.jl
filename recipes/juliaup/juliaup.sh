#!/usr/bin/env bash
# Wrapper around juliaup for the {{APP_NAME}} distribution.
#
# juliaup downloads from whatever host JULIAUP_SERVER points at, so no patched client is
# needed. The depot is kept separate from ~/.julia/juliaup so this distribution and a stock
# Julia installation do not share channels or state.

command -v juliaup >/dev/null || {
  echo "{{APP_NAME}}-juliaup: juliaup is not installed or not on the PATH. See https://github.com/JuliaLang/juliaup" >&2
  exit 127
}

export JULIAUP_SERVER={{{JULIAUP_SERVER}}}
export JULIAUP_DEPOT_PATH="${HOME}/.julia/juliaup-depots/{{JULIAUP_DEPOT}}"

exec juliaup "$@"
