@echo off
REM Windows PowerShell 5.1-compatible launcher. Run from cmd.exe so fab has a Windows console.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-FabricInventory.ps1" %*
