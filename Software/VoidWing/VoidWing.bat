@echo off
rem Starts VOID WING with the portable Godot 4.7.2. The MARS GUI's GAME screen can launch this file.
set GODOT=D:\SOFTWARE\Godot\Godot_v4.7.2-stable_win64.exe
if not exist "%GODOT%" (
  echo Godot not found at %GODOT%
  echo Download Godot 4.7 from https://godotengine.org and fix the path in this file.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
