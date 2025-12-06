#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # $0 can also be a relative path

{{#JULIA_APP_BUNDLE}}

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

{{/JULIA_APP_BUNDLE}}

{{#JULIAC_BUNDLE}}

CMD="$SCRIPT_DIR/bin/{{APP_NAME_LOWERCASE}}"
{{^WINDOWED}}
if [ $# -eq 0 ]; then
    osascript -e 'tell application "Terminal" to activate' \
              -e 'tell application "Terminal" to do script "clear && '"$CMD"'; exit"'
    exit 0
fi
{{/WINDOWED}}

# Arguments provided: Execute in current shell
"$CMD" $@

{{/JULIAC_BUNDLE}}
