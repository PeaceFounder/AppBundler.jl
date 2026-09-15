#!/bin/bash
# Generic entry point for a non-Julia payload.

if [ -z "${APPDIR}" ]; then
    APPDIR=$(cd -P "$(dirname "$(readlink -f "$0")")" >/dev/null 2>&1 && pwd)
fi

exec "${APPDIR}/bin/{{APP_NAME}}" "$@"
