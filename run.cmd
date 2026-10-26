@echo off
rem Paris Walk (Godot): run.cmd  /  start straight into hard mode: run.cmd hard
set "GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine.Mono_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  exit /b 1
)
if /i "%~1"=="hard" (
  start "" "%GODOT%" --path "%~dp0." -- --autoplay --hard
) else (
  start "" "%GODOT%" --path "%~dp0."
)
