#!/bin/bash

JULIA="$SNAP/bin/julia"

# Let's force precompilation for wayland even on headless system
export WAYLAND_DISPLAY=wayland-0

echo "$(date): Precompilation started" >> $SNAP_DATA/configure.log

$JULIA --eval="__precompile__()" # This may work

echo "$(date): Precompilation finished" >> $SNAP_DATA/configure.log
