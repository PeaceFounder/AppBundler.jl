#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # $0 can also be a relative path
JULIA="$SCRIPT_DIR/bin/julia"

{{^WINDOWED}}
if [ $# -eq 0 ]; then
    osascript -e 'tell application "Terminal" to activate' \
              -e 'tell application "Terminal" to do script "clear && '"$JULIA"' {{#MODULE_NAME}}--eval=\"using {{MODULE_NAME}}\" -- {{/MODULE_NAME}}; exit"'
    exit 0
fi
{{/WINDOWED}}

# Arguments provided: Execute in current shell
"$JULIA"{{#MODULE_NAME}} --eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}} $@
