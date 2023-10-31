$APP_NAME="{{APP_NAME}}"
$ROOT=$PSScriptRoot

$JULIA="$PSScriptRoot\julia\bin\julia.exe"

$env:JULIA_LOAD_PATH="$ROOT\packages;@stdlib;@"
$env:JULIA_DEPOT_PATH="$ROOT"
$env:JULIA_PROJECT="$ROOT\$APP_NAME"

& $JULIA --startup-file=no "$ROOT\startup\precompile.jl"