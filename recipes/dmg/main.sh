#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"   # .../MyApp.app/Contents/MacOS
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"      # .../MyApp.app/Contents

#COMMAND=(Libraries/bin/julia --eval 'using GtkApp' --)
COMMAND=({{{COMMAND}}})

# First element is always relative to BASE_DIR
CMD=("$BASE_DIR/${COMMAND[0]}" "${COMMAND[@]:1}")

# POSIX single-quote one argument: abc'd -> 'abc'\''d'
# Understood by bash, zsh, fish and tcsh alike
shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

{{^WINDOWED}}
if [ $# -eq 0 ]; then
    # No arguments (e.g. launched from Finder): open in a new Terminal window
    SHELL_CMD="clear;"
    for arg in "${CMD[@]}"; do
        SHELL_CMD+=" $(shell_quote "$arg")"
    done
    SHELL_CMD+="; exit"

    osascript -e 'on run argv' \
              -e 'tell application "Terminal" to activate' \
              -e 'tell application "Terminal" to do script (item 1 of argv)' \
              -e 'end run' \
              "$SHELL_CMD"
    exit 0
fi
{{/WINDOWED}}

# Arguments provided: replace this process with Julia
exec "${CMD[@]}" "$@"





# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # $0 can also be a relative path

# COMMAND=({{{COMMAND}}})

# JULIA="$SCRIPT_DIR/bin/julia"
# {{^WINDOWED}}
# if [ $# -eq 0 ]; then
#     osascript -e 'tell application "Terminal" to activate' \
#               -e 'tell application "Terminal" to do script "clear && '"$JULIA"' {{#MODULE_NAME}}--eval=\"using {{MODULE_NAME}}\" -- {{/MODULE_NAME}}; exit"'
#     exit 0
# fi
# {{/WINDOWED}}
# # Arguments provided: Execute in current shell
# "$JULIA"{{#MODULE_NAME}} --eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}} $@
