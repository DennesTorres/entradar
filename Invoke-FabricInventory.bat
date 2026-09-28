@echo off
REM Run through cmd.exe because fab CLI 1.0.1 expects a Windows console for definition commands.
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-FabricInventory.ps1" %*
