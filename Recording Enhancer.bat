@echo off
rem Recording Enhancer launcher - opens the UI without keeping a console window
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0enhance-gui.ps1"
