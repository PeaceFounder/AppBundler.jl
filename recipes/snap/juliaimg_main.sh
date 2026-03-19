#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/julia"
$JULIA {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}} $@
