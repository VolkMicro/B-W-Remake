@echo off
setlocal
cd /d "%~dp0"
set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
if not defined BW_GAME_DIR set "BW_GAME_DIR=C:\Games\Black and White Complete Collection"
if not exist "%BW_GAME_DIR%\Data\AllMeshes.g3d" (
    echo Original Black and White data was not found.
    echo Set BW_GAME_DIR to your original installation folder.
    pause
    exit /b 1
)
"%~dp0GodotIsland-village-preview9.exe" --log-file "%~dp0preview.log" -- "--bw=%BW_GAME_DIR%" --story-preview
if errorlevel 1 (
    echo Preview stopped with an error. See preview.log in this folder.
    pause
)
endlocal
