@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem python.exe on this box resolves to a broken System32 stub, so try the
rem launcher first and only then fall back to PATH names.
set "PY=py -3"
if not exist "%SystemRoot%\py.exe" set "PY=python"
"%PY%" build-custom\build_and_install.py %*
if errorlevel 1 (echo. & echo [FAILED] see the log above)
pause
