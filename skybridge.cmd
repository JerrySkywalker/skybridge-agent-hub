@echo off
setlocal
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0skybridge.ps1" %*
exit /b %ERRORLEVEL%
