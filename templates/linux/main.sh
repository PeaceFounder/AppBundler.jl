#!/bin/bash

APP_NAME={{APP_NAME}}
export USER_DATA=$SNAP_USER_DATA

JULIA="$SNAP/lib/julia/bin/julia"

export JULIA_LOAD_PATH="$SNAP/lib/packages:@stdlib:@" 
export JULIA_PROJECT="$SNAP/lib/$APP_NAME"

JULIA_MAIN="$SNAP/lib/$APP_NAME/main.jl"

export JULIA_DEPOT_PATH="$SNAP_USER_COMMON/cache/"
export JULIA_DEPOT_PATH="$JULIA_DEPOT_PATH:$SNAP_DATA/cache/"
export JULIA_DEPOT_PATH="$JULIA_DEPOT_PATH:$SNAP/lib/"

$JULIA --startup-file=no -L "$SNAP/lib/startup/init.jl" $JULIA_MAIN
