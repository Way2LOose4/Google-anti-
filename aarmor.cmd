@echo off
rem armor 入口：优先 PATH 里的 node，否则依次试常见安装位置
setlocal enabledelayedexpansion
set "CLI=%~dp0src\cli.mjs"
set "NODE="

for %%i in (node.exe) do if not defined NODE set "NODE=%%~$PATH:i"

if not defined NODE for %%p in (
  "%ProgramFiles%\nodejs\node.exe"
  "%LOCALAPPDATA%\Programs\nodejs\node.exe"
  "%USERPROFILE%\.workbuddy\binaries\node\versions\*\node.exe"
) do if not defined NODE if exist "%%~p" set "NODE=%%~p"

if not defined NODE (
  echo [aarmor] node not found. Install Node.js 20+ or add it to PATH.
  exit /b 1
)

"%NODE%" "%CLI%" %*
