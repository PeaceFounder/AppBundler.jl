# Wrapper around juliaup for the {{APP_NAME}} distribution.
#
# juliaup downloads from whatever host JULIAUP_SERVER points at, so no patched client is
# needed. The depot is kept separate from the default one so this distribution and a stock
# Julia installation do not share channels or state.

if (-not (Get-Command juliaup -ErrorAction SilentlyContinue)) {
    Write-Error "{{APP_NAME}}-juliaup: juliaup is not installed or not on the PATH. See https://github.com/JuliaLang/juliaup"
    exit 127
}

$env:JULIAUP_SERVER = "{{{JULIAUP_SERVER}}}"
$env:JULIAUP_DEPOT_PATH = Join-Path $HOME ".julia\juliaup-depots\{{JULIAUP_DEPOT}}"

& juliaup @args
exit $LASTEXITCODE
