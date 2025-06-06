#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/../lib/julia/bin/julia"
$JULIA --eval="__main__()"
