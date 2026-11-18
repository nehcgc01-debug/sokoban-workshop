@echo off
setlocal DisableDelayedExpansion
if not exist "%~dp0Start_BlindTest.exe" (
  echo Missing Start_BlindTest.exe. Extract the complete host package to a new folder.
  pause
  exit /b 1
)
start "" /wait "%~dp0Start_BlindTest.exe"
exit /b %ERRORLEVEL%
