#!/bin/bash
# Entry point the AppImage runtime executes after mounting the bundled filesystem.
#
# $APPDIR is set by the runtime and points at the mount point. It is absent when the AppDir is
# executed directly (during a build, or after --appimage-extract), so fall back to resolving it
# from this script's own location.

if [ -z "${APPDIR}" ]; then
    APPDIR=$(cd -P "$(dirname "$(readlink -f "$0")")" >/dev/null 2>&1 && pwd)
fi

{{#APP_DEPOT}}
# Persist the depot under a per-user directory rather than the mount point, which is read-only and
# disappears when the AppImage exits. AppEnv reads USER_DATA in startup.jl to place the depot.
if [ -z "${USER_DATA}" ]; then
    export USER_DATA="${XDG_DATA_HOME:-${HOME}/.local/share}/{{APP_NAME}}"
fi
{{/APP_DEPOT}}

exec "${APPDIR}/bin/julia" {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}}"$@"
