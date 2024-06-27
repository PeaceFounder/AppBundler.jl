$JULIA="$PSScriptRoot\julia\bin\julia.exe"

$env:JULIA_LOAD_PATH="$PSScriptRoot\packages;@stdlib;@"
$env:JULIA_DEPOT_PATH="$PSScriptRoot"
$env:JULIA_PROJECT="$PSScriptRoot\{{APP_NAME}}"

& $JULIA --startup-file=no "$PSScriptRoot\startup\precompile.jl"