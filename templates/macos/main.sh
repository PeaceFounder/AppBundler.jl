#!/bin/bash

SCRIPT_DIR=$(dirname "$0")
BUNDLE_DIR=$(realpath $(dirname $(dirname $SCRIPT_DIR)))

APP_NAME={{APP_NAME}}
WITH_SPLASH_SCREEN={{WITH_SPLASH_SCREEN}}

JULIA_HOME="$SCRIPT_DIR/../Frameworks/julia"
export JULIA="$JULIA_HOME/bin/julia"

HOME=realpath ~
export USER_DATA="$HOME/.config/$APP_NAME"
mkdir -p "$USER_DATA"

export JULIA_LOAD_PATH="$SCRIPT_DIR/../Frameworks/packages:@stdlib:@" 
export JULIA_PROJECT="$SCRIPT_DIR/../Frameworks/$APP_NAME"

export JULIA_ARTIFACT_OVERRIDE="$SCRIPT_DIR/../Frameworks/artifacts"

JULIA_MAIN="$SCRIPT_DIR/../Frameworks/$APP_NAME/main.jl"

CACHE_DIR="$(realpath ~)/.cache/$APP_NAME"

export JULIA_DEPOT_PATH="$CACHE_DIR:$SCRIPT_DIR/../Frameworks/"

PRECOMPILED="$CACHE_DIR/precompiled"

if [ -e $PRECOMPILED ] || [ -d "$SCRIPT_DIR/../Frameworks/compiled" ]; then

    $JULIA --startup-file=no -L "$SCRIPT_DIR/../Frameworks/startup/init.jl" $JULIA_MAIN
    
else

    if $WITH_SPLASH_SCREEN ; then
        $JULIA --startup-file=no "$SCRIPT_DIR/../Frameworks/startup/configure.jl"
    else
        $JULIA --startup-file=no "$SCRIPT_DIR/../Frameworks/startup/precompile.jl"
    fi

    mkdir -p $(dirname $PRECOMPILED)
    touch "$PRECOMPILED"
    open --new $BUNDLE_DIR

fi
