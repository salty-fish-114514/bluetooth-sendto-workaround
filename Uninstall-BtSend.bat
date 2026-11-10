@echo off
setlocal
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-BtSend.ps1" -Uninstall
set EXITCODE=%ERRORLEVEL%
popd
if not defined NO_PAUSE pause
exit /b %EXITCODE%
