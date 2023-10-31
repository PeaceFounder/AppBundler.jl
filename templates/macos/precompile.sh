#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

APP_NAME={{APP_NAME}}

JULIA_HOME="$SCRIPT_DIR/../Frameworks/julia"
export JULIA="$JULIA_HOME/bin/julia"

export USER_DATA="~/.config/$APP_NAME/"

export JULIA_LOAD_PATH="$SCRIPT_DIR/../Frameworks/packages:@stdlib:@" 
export JULIA_PROJECT="$SCRIPT_DIR/../Frameworks/$APP_NAME"

JULIA_MAIN="$SCRIPT_DIR/../Frameworks/$APP_NAME/main.jl"

export JULIA_DEPOT_PATH="$SCRIPT_DIR/../Frameworks/"

$JULIA --startup-file=no "$SCRIPT_DIR/../Frameworks/precompile.jl"
