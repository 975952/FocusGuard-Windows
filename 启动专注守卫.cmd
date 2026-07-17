@echo off
setlocal
if exist "%~dp0FocusGuard.exe" (
    if "%~1"=="" if exist "%~dp0FocusGuard.Splash.exe" start "" "%~dp0FocusGuard.Splash.exe"
    start "" "%~dp0FocusGuard.exe" %*
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0FocusGuard.ps1" %*
)

