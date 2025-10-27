#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/julia"
$JULIA --eval="using {{MODULE_NAME}}" -- "$@"
