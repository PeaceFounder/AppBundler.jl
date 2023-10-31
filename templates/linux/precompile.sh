#!/bin/bash

SNAP="$(dirname "$0")/../"
APP_NAME={{APP_NAME}}

JULIA="$SNAP/lib/julia/bin/julia"

export JULIA_LOAD_PATH="$SNAP/lib/packages:@stdlib:@" 
export JULIA_PROJECT="$SNAP/lib/$APP_NAME"
export JULIA_DEPOT_PATH="$SNAP/lib/"

$JULIA --startup-file=no "$SNAP/lib/startup/precompile.jl"
