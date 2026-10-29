@echo off
REM Double-click to mirror your phone. Arguments are passed through, e.g. phone.bat -Audio
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phone.ps1" %*
if errorlevel 1 pause
