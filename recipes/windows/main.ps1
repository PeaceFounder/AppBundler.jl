$env:USER_DATA = "$env:Temp\{{APP_NAME}}"
New-Item -ItemType Directory -Path $env:USER_DATA -ErrorAction Ignore
$JULIA="$PSScriptRoot\julia\bin\julia.exe"
& $JULIA --startup-file=no "$PSScriptRoot\main.jl"