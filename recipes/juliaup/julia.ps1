# Launches julia from the {{APP_NAME}} distribution.
#
# Install a channel first with `{{APP_NAME}}-juliaup add {{JULIAUP_CHANNEL}}`.

if (-not (Get-Command julia -ErrorAction SilentlyContinue)) {
    Write-Error "{{APP_NAME}}-julia: julia is not installed or not on the PATH. Install it using juliaup, see https://github.com/JuliaLang/juliaup"
    exit 127
}

$env:JULIAUP_SERVER = "{{{JULIAUP_SERVER}}}"
$env:JULIAUP_DEPOT_PATH = Join-Path $HOME ".julia\juliaup-depots\{{JULIAUP_DEPOT}}"

& julia @args
exit $LASTEXITCODE
