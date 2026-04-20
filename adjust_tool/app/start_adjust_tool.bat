@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PROXY_PORT=8787"
set "WEB_PORT=5500"
set "PROXY_PS_SCRIPT=%ROOT%\proxy.ps1"
set "PROXY_JS_SCRIPT=%ROOT%\proxy.js"

cd /d "%ROOT%"

set "PROXY_PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PROXY_PORT%" ^| findstr "LISTENING"') do (
  set "PROXY_PID=%%p"
)

if defined PROXY_PID (
  echo [INFO] Proxy already running on port %PROXY_PORT% ^(PID: %PROXY_PID%^).
) else (
  if exist "%PROXY_JS_SCRIPT%" (
    where node >nul 2>&1
    if errorlevel 1 (
      if exist "%PROXY_PS_SCRIPT%" (
        echo [WARN] Node.js not found. Fallback to PowerShell proxy...
        start "Adjust Proxy" powershell -NoExit -ExecutionPolicy Bypass -File "%PROXY_PS_SCRIPT%"
      ) else (
        echo [ERROR] Node.js not found and proxy.ps1 is missing.
        echo Please install Node.js 18+ or restore "%PROXY_PS_SCRIPT%".
        pause
        exit /b 1
      )
    ) else (
      echo [INFO] Starting proxy server via Node.js...
      start "Adjust Proxy" cmd /k "cd /d ""%ROOT%"" && node ""%PROXY_JS_SCRIPT%"""
    )
  ) else (
    if exist "%PROXY_PS_SCRIPT%" (
      echo [INFO] proxy.js not found. Starting proxy server via PowerShell...
      start "Adjust Proxy" powershell -NoExit -ExecutionPolicy Bypass -File "%PROXY_PS_SCRIPT%"
    ) else (
      echo [ERROR] No proxy script found. Expected:
      echo         %PROXY_JS_SCRIPT%
      echo         %PROXY_PS_SCRIPT%
      pause
      exit /b 1
    )
  )
  timeout /t 2 >nul
)

echo [INFO] Checking proxy readiness on port %PROXY_PORT%...
call :wait_for_port %PROXY_PORT% 20 PROXY_READY
if /i not "%PROXY_READY%"=="ON" (
  echo [ERROR] Proxy is not ready on port %PROXY_PORT%.
  echo Please check the "Adjust Proxy" window for startup errors.
  pause
  exit /b 1
)
echo [OK] Proxy is ready on port %PROXY_PORT%.

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
start "Adjust Web" cmd /k "cd /d ""%ROOT%"" && python -m http.server %WEB_PORT%"
timeout /t 2 >nul
start "" "http://localhost:%WEB_PORT%/index.html"

exit /b 0

:wait_for_port
set "TARGET_PORT=%~1"
set "MAX_RETRY=%~2"
set /a RETRY=0

:wait_for_port_loop
call :check_port %TARGET_PORT% PORT_STATUS
if /i "%PORT_STATUS%"=="ON" (
  set "%~3=ON"
  exit /b 0
)

set /a RETRY+=1
if %RETRY% GEQ %MAX_RETRY% (
  set "%~3=OFF"
  exit /b 0
)

timeout /t 1 >nul
goto wait_for_port_loop

:check_port
set "TARGET_PORT=%~1"
set "RESULT=OFF"
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%TARGET_PORT%" ^| findstr "LISTENING"') do (
  set "RESULT=ON"
  goto check_port_done
)

:check_port_done
set "%~2=%RESULT%"
exit /b 0
