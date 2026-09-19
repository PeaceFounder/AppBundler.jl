#!/bin/bash
# Entry point the AppImage runtime executes after mounting the bundled filesystem.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)" # $0 can also be a relative path
exec "${SCRIPT_DIR}/bin/julia" {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}}"$@"
