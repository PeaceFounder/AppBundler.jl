#!/bin/bash

APP_NAME={{APP_NAME}}
JULIA="$SNAP/lib/julia/bin/julia"

export JULIA_LOAD_PATH="$SNAP/lib/packages:@stdlib:@" 
export JULIA_PROJECT="$SNAP/lib/$APP_NAME"

export JULIA_DEPOT_PATH="$SNAP_DATA/cache/"
export JULIA_DEPOT_PATH="$JULIA_DEPOT_PATH:$SNAP/lib/"

# Let's force precompilation for wayland even on headless system
export WAYLAND_DISPLAY=wayland-0

echo "$(date): Precompilation started" >> $SNAP_DATA/configure.log

$JULIA --startup-file=no "$SNAP/lib/startup/precompile.jl"

echo "$(date): Precompilation finished" >> $SNAP_DATA/configure.log
