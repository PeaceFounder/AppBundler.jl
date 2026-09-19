#!/bin/bash
# Generic entry point for a non-Julia payload.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # $0 can also be a relative path
exec "${SCRIPT_DIR}/bin/{{APP_NAME}}" "$@"
