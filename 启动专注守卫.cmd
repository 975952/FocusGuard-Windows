@echo off
setlocal
if exist "%~dp0FocusGuard.exe" (
    start "" "%~dp0FocusGuard.exe" %*
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0FocusGuard.ps1" %*
)

