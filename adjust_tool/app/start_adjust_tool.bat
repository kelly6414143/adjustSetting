@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PROXY_PORT=8787"
set "WEB_PORT=5500"

cd /d "%ROOT%"

where node >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Node.js is not installed or not in PATH.
  echo Please install Node.js 18+ first.
  pause
  exit /b 1
)

set "PROXY_PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PROXY_PORT%" ^| findstr "LISTENING"') do (
  set "PROXY_PID=%%p"
)

if defined PROXY_PID (
  echo [INFO] Proxy already running on port %PROXY_PORT% ^(PID: %PROXY_PID%^).
) else (
  echo [INFO] Starting proxy server...
  start "Adjust Proxy" cmd /k "cd /d "%ROOT%" && node proxy.js"
  timeout /t 2 >nul
)

set "WEB_PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%WEB_PORT%" ^| findstr "LISTENING"') do (
  set "WEB_PID=%%p"
)

if defined WEB_PID (
  echo [INFO] Web server already running on port %WEB_PORT% ^(PID: %WEB_PID%^).
  start "" "http://localhost:%WEB_PORT%/index.html"
  exit /b 0
)

where python >nul 2>&1
if errorlevel 1 (
  echo [WARN] Python not found. Opening index.html directly...
  start "" "%ROOT%\index.html"
  exit /b 0
)

echo [INFO] Starting local web server on port %WEB_PORT%...
start "Adjust Web" cmd /k "cd /d "%ROOT%" && python -m http.server %WEB_PORT%"
timeout /t 2 >nul
start "" "http://localhost:%WEB_PORT%/index.html"

exit /b 0
