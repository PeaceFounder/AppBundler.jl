#!/bin/bash

# Resolve the real bundle directory even when invoked through a PATH symlink
# (e.g. /usr/local/bin/{{APP_NAME}} -> /opt/{{APP_NAME}}/bin/{{APP_NAME}}):
# readlink -f follows the link so JULIA points at the bundle's own julia.
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
JULIA="$SCRIPT_DIR/julia"

# Persist app state under an XDG-conventional directory unless already set.
# AppEnv reads USER_DATA in startup.jl to place the Julia depot cache there.
if [ -z "${USER_DATA}" ]; then
    export USER_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}/{{APP_DISPLAY_NAME}}"
fi

exec "$JULIA" {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}}"$@"
