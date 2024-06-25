#!/bin/bash

SCRIPT_DIR=$(dirname "$0")
BUNDLE_DIR=$(realpath $(dirname $(dirname $SCRIPT_DIR)))

APP_NAME={{APP_NAME}}
WITH_SPLASH_SCREEN={{WITH_SPLASH_SCREEN}}

JULIA_HOME="$SCRIPT_DIR/../Libraries/julia"
export JULIA="$JULIA_HOME/bin/julia"

if [ -z "$APP_SANDBOX_CONTAINER_ID" ]; then
    echo "Running outside SandBox environment"

    CACHE_DIR="$HOME/.cache/$APP_NAME"
    export USER_DATA="$HOME/.config/$APP_NAME"
else
    echo "Running in a SandBox environment"

    CACHE_DIR="$HOME/Library/Caches/depot"
    export USER_DATA="$HOME/Library/Application Support/Local"
fi

mkdir -p "$USER_DATA"

export JULIA_LOAD_PATH="$SCRIPT_DIR/../Libraries/packages:@stdlib:@" 
export JULIA_PROJECT="$SCRIPT_DIR/../Libraries/$APP_NAME"

JULIA_MAIN="$SCRIPT_DIR/../Libraries/$APP_NAME/main.jl"

export JULIA_DEPOT_PATH="$CACHE_DIR:$SCRIPT_DIR/../Libraries/"

PRECOMPILED="$CACHE_DIR/precompiled"

if [ -e $PRECOMPILED ] || [ -d "$SCRIPT_DIR/../Libraries/compiled" ]; then

    $JULIA --startup-file=no -L "$SCRIPT_DIR/../Libraries/startup/init.jl" $JULIA_MAIN
    
else

    if $WITH_SPLASH_SCREEN ; then
        $JULIA --startup-file=no "$SCRIPT_DIR/../Libraries/startup/configure.jl"
    else
        $JULIA --startup-file=no "$SCRIPT_DIR/../Libraries/startup/precompile.jl"
    fi

    mkdir -p $(dirname $PRECOMPILED)
    touch "$PRECOMPILED"
    open --new $BUNDLE_DIR # This likelly does not work in a sandbox

fi
