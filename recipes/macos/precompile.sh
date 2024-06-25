#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

APP_NAME={{APP_NAME}}

JULIA_HOME="$SCRIPT_DIR/../Libraries/julia"
export JULIA="$JULIA_HOME/bin/julia"

export USER_DATA="~/.config/$APP_NAME/"

export JULIA_LOAD_PATH="$SCRIPT_DIR/../Libraries/packages:@stdlib:@" 
export JULIA_PROJECT="$SCRIPT_DIR/../Libraries/$APP_NAME"

JULIA_MAIN="$SCRIPT_DIR/../Libraries/$APP_NAME/main.jl"

export JULIA_DEPOT_PATH="$SCRIPT_DIR/../Libraries/"

$JULIA --startup-file=no "$SCRIPT_DIR/../Libraries/startup/precompile.jl"
