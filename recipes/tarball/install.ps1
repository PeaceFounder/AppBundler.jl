<#
Installer for {{APP_DISPLAY_NAME}} {{APP_VERSION}} (Windows).

Copies this unpacked bundle to %LOCALAPPDATA%\Programs\{{APP_NAME}} and creates
a Start Menu shortcut. Per-user state (chats, projects, depot cache) lives under
%LOCALAPPDATA%\{{APP_DISPLAY_NAME}} and is never touched by install/uninstall.

Usage:
  powershell -ExecutionPolicy Bypass -File install.ps1 [-Prefix DIR] [-Uninstall]

If you'd rather not install, just run bin\{{APP_NAME}}.bat from the unpacked folder.
#>
param(
    [string]$Prefix = (Join-Path $env:LOCALAPPDATA "Programs\{{APP_NAME}}"),
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$AppName = "{{APP_NAME}}"
$AppDisplayName = "{{APP_DISPLAY_NAME}}"
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$Shortcut = Join-Path $StartMenu "$AppDisplayName.lnk"

if ($Uninstall) {
    Write-Host "Removing $AppDisplayName from $Prefix..."
    if (Test-Path $Shortcut) { Remove-Item $Shortcut -Force }
    if (Test-Path $Prefix)   { Remove-Item $Prefix -Recurse -Force }
    Write-Host "Done. (Per-user data was left intact.)"
    exit 0
}

$SrcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($SrcDir -eq $Prefix) {
    Write-Error "Refusing to install into the bundle's own directory ($Prefix). Unpack elsewhere or pass -Prefix."
    exit 1
}

Write-Host "Installing $AppDisplayName to $Prefix..."
if (Test-Path $Prefix) { Remove-Item $Prefix -Recurse -Force }
New-Item -ItemType Directory -Path $Prefix -Force | Out-Null
Copy-Item -Path (Join-Path $SrcDir "*") -Destination $Prefix -Recurse -Force

$Launcher = Join-Path $Prefix "bin\$AppName.bat"
New-Item -ItemType Directory -Path $StartMenu -Force | Out-Null
$WshShell = New-Object -ComObject WScript.Shell
$lnk = $WshShell.CreateShortcut($Shortcut)
$lnk.TargetPath = $Launcher
$lnk.WorkingDirectory = (Join-Path $Prefix "bin")
$lnk.Save()

Write-Host ""
Write-Host "$AppDisplayName installed."
Write-Host "  Run:       Start Menu -> $AppDisplayName  (or $Launcher)"
Write-Host "  Uninstall: powershell -ExecutionPolicy Bypass -File `"$Prefix\install.ps1`" -Uninstall"
