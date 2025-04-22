#!/bin/bash

SCRIPT_DIR=$(dirname "$0")
BUNDLE_DIR=$(realpath $(dirname $(dirname $SCRIPT_DIR)))

APP_NAME={{APP_NAME}}
#WITH_SPLASH_SCREEN={{WITH_SPLASH_SCREEN}}

JULIA="$SCRIPT_DIR/julia/bin/julia"
$JULIA -L "$SCRIPT_DIR/startup/init.jl" "$SCRIPT_DIR/{{MODULE_NAME}}/main.jl"
