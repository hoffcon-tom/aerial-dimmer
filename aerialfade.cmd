@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0aerialfade.ps1" %*
exit /b %ERRORLEVEL%
