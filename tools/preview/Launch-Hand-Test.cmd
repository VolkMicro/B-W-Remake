@echo off
setlocal
cd /d "%~dp0"
set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
if not defined BW_GAME_DIR set "BW_GAME_DIR=C:\Games\Black and White Complete Collection"
if not defined BW_GODOT set "BW_GODOT=%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe"
if not exist "%BW_GODOT%" (
    echo Godot is required for this developer test. Use Launch-Story-Preview.cmd for the normal game.
    pause
    exit /b 1
)
"%BW_GODOT%" --path "%~dp0..\..\game" --script res://tests/verify_resource_input.gd --log-file "%~dp0hand-test.log" -- "--bw=%BW_GAME_DIR%" --manual
endlocal
