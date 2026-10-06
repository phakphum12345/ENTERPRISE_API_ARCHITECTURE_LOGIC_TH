@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0platform\recon-sync\recon-sync-engine.ps1" -Command audit
exit /b %errorlevel%
