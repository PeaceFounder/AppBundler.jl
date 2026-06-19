#!/bin/bash

# Resolve the real bundle directory even when invoked through a PATH symlink
# (e.g. /usr/local/bin/{{APP_NAME}} -> /opt/{{APP_NAME}}/bin/{{APP_NAME}}).
# Done portably (no `readlink -f`, which BSD/macOS lacks) so this one launcher
# serves both Linux and macOS.
SOURCE="$0"
while [ -h "$SOURCE" ]; do
    DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
    SOURCE=$(readlink "$SOURCE")
    case "$SOURCE" in /*) ;; *) SOURCE="$DIR/$SOURCE" ;; esac
done
SCRIPT_DIR=$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)
JULIA="$SCRIPT_DIR/julia"

# Persist app state under a platform-conventional directory unless already set.
# AppEnv reads USER_DATA in startup.jl to place the Julia depot cache there.
if [ -z "${USER_DATA}" ]; then
    case "$(uname -s)" in
        Darwin) export USER_DATA="${HOME}/Library/Application Support/{{APP_DISPLAY_NAME}}" ;;
        *)      export USER_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}/{{APP_DISPLAY_NAME}}" ;;
    esac
fi

exec "$JULIA" {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}}"$@"
