@echo off
setlocal enableextensions

rem Launcher for {{APP_DISPLAY_NAME}} on Windows. Sits in bin\ next to the
rem bundle's own julia.exe; %~dp0 is this script's directory (trailing slash).
set "SCRIPT_DIR=%~dp0"
set "JULIA=%SCRIPT_DIR%julia.exe"

rem Persist app state under %LOCALAPPDATA% unless already set. AppEnv reads
rem USER_DATA in startup.jl to place the Julia depot cache there.
if "%USER_DATA%"=="" set "USER_DATA=%LOCALAPPDATA%\{{APP_DISPLAY_NAME}}"
rem On Windows AppEnv requires USER_DATA to exist (an MSIX sandbox provides
rem it), so a first start from a tarball would exit right away.
if not exist "%USER_DATA%\" mkdir "%USER_DATA%"

"%JULIA%" {{#MODULE_NAME}}--eval="using {{MODULE_NAME}}" -- {{/MODULE_NAME}}%*
