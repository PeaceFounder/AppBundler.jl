#!/bin/bash

SCRIPT_DIR=$(dirname "$0")

JULIA="$SCRIPT_DIR/julia"
$JULIA "$@"
