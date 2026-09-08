@echo off
rem ============================================================
rem  publish.cmd - Windows Task Scheduler entry point
rem  Copies index.html -> yyyyMMdd.html, commits and pushes
rem  to the current branch. No parameters required.
rem ============================================================
setlocal EnableExtensions
chcp 65001 >nul 2>&1

rem --- locate script directory (Task Scheduler safe) ---
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

rem --- resolve powershell.exe ---
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" set "PS_EXE=powershell.exe"

rem --- log file: logs\publish_yyyyMMdd.log ---
set "LOG_DIR=%SCRIPT_DIR%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

rem date slicing depends on locale; fall back to PowerShell when not 8 digits
set "STAMP=%date:~0,4%%date:~5,2%%date:~8,2%"
echo %STAMP%| findstr /r "^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$" >nul
if errorlevel 1 (
    for /f "usebackq delims=" %%i in (`"%PS_EXE%" -NoProfile -NonInteractive -Command "Get-Date -Format yyyyMMdd"`) do set "STAMP=%%i"
)
set "LOG_FILE=%LOG_DIR%\publish_%STAMP%.log"

echo ============================================================ >> "%LOG_FILE%"
echo [%date% %time%] Task started >> "%LOG_FILE%"
echo Script dir : %SCRIPT_DIR% >> "%LOG_FILE%"

if not exist "%SCRIPT_DIR%\publish.ps1" (
    echo [ERROR] publish.ps1 not found in %SCRIPT_DIR% >> "%LOG_FILE%"
    echo [ERROR] publish.ps1 not found in %SCRIPT_DIR%
    endlocal & exit /b 2
)

"%PS_EXE%" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\publish.ps1" >> "%LOG_FILE%" 2>&1
set "RC=%ERRORLEVEL%"

echo [%date% %time%] Task finished, exit code=%RC% >> "%LOG_FILE%"

if not "%RC%"=="0" (
    echo [ERROR] Failed with exit code %RC%. See log: %LOG_FILE%
) else (
    echo [OK] Done. Log: %LOG_FILE%
)

endlocal & exit /b %RC%
