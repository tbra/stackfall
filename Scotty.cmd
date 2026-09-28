@echo off
powershell.exe -NoProfile -File "%~dp0tools\start_scotty.ps1" %*
if errorlevel 1 pause
