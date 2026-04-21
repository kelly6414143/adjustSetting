@echo off
chcp 65001 >nul
setlocal

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "PROXY_PORT=8787"
set "WEB_PORT=5500"
set "WEB_URL=http://localhost:%WEB_PORT%/index.html"
set "PROXY_PS_SCRIPT=%ROOT%\proxy.ps1"
set "WEB_PS_SCRIPT=%ROOT%\web_server.ps1"
set "CONTROL_LOG_DIR=%ROOT%\.."
set "RUNTIME_DIR=%ROOT%\.runtime"
set "PROXY_PID_FILE=%RUNTIME_DIR%\proxy.pid"
set "WEB_PID_FILE=%RUNTIME_DIR%\web.pid"

cd /d "%ROOT%"
if errorlevel 1 (
  echo [FATAL] [start_adjust_tool] Failed to cd into "%ROOT%".
  exit /b 1
)
call :init_log
call :log INFO "start_adjust_tool started."
call :log INFO "Args: %*"
call :ensure_runtime_dir

set "PROXY_PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PROXY_PORT%" ^| findstr "LISTENING"') do (
  set "PROXY_PID=%%p"
)

if defined PROXY_PID (
  call :log INFO "Proxy already running on port %PROXY_PORT% (PID: %PROXY_PID%)."
) else (
  if exist "%PROXY_PS_SCRIPT%" (
    call :log INFO "Starting proxy server via PowerShell."
    start "Adjust Proxy" powershell -NoExit -ExecutionPolicy Bypass -Command "$host.UI.RawUI.WindowTitle='Adjust Proxy'; & '%PROXY_PS_SCRIPT%'"
    timeout /t 1 >nul
    call :resolve_pid_by_title "Adjust Proxy" STARTED_PROXY_PID
    if not defined STARTED_PROXY_PID (
      call :log WARN "Could not resolve Proxy window PID by title."
    ) else (
      > "%PROXY_PID_FILE%" echo %STARTED_PROXY_PID%
      call :log INFO "Proxy PowerShell PID recorded: %STARTED_PROXY_PID%"
    )
  ) else (
    call :log ERROR "proxy.ps1 is missing."
    call :log ERROR "Please restore %PROXY_PS_SCRIPT%."
    pause
    exit /b 1
  )
  timeout /t 2 >nul
)

call :log INFO "Checking proxy readiness on port %PROXY_PORT%."
call :wait_for_port %PROXY_PORT% 20 PROXY_READY
if /i not "%PROXY_READY%"=="ON" (
  call :log ERROR "Proxy is not ready on port %PROXY_PORT%."
  call :log ERROR "Please check the Adjust Proxy window for startup errors."
  pause
  exit /b 1
)
call :log INFO "Proxy is ready on port %PROXY_PORT%."

set "WEB_PID="
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%WEB_PORT%" ^| findstr "LISTENING"') do (
  set "WEB_PID=%%p"
)

if defined WEB_PID (
  call :log INFO "Web server already running on port %WEB_PORT% (PID: %WEB_PID%)."
) else (
  if not exist "%WEB_PS_SCRIPT%" (
    call :log ERROR "web_server.ps1 is missing: %WEB_PS_SCRIPT%"
    pause
    exit /b 1
  )
  call :log INFO "Starting PowerShell web server on port %WEB_PORT%."
  start "Adjust Web" powershell -NoExit -ExecutionPolicy Bypass -Command "$host.UI.RawUI.WindowTitle='Adjust Web'; & '%WEB_PS_SCRIPT%' -Port %WEB_PORT% -RootPath '%ROOT%'"
  timeout /t 1 >nul
  call :resolve_pid_by_title "Adjust Web" STARTED_WEB_PID
  if not defined STARTED_WEB_PID (
    call :log WARN "Could not resolve Web window PID by title."
  ) else (
    > "%WEB_PID_FILE%" echo %STARTED_WEB_PID%
    call :log INFO "Web PowerShell PID recorded: %STARTED_WEB_PID%"
  )
)

call :log INFO "Checking web readiness on port %WEB_PORT%."
call :wait_for_port %WEB_PORT% 20 WEB_READY
if /i not "%WEB_READY%"=="ON" (
  call :log ERROR "Web server is not ready on port %WEB_PORT%."
  pause
  exit /b 1
)

call :log INFO "Opening web url: %WEB_URL%"
start "" "%WEB_URL%"
if errorlevel 1 (
  call :log ERROR "Failed to open web url: %WEB_URL%"
  pause
  exit /b 1
)
call :log INFO "start_adjust_tool completed."

exit /b 0

:ensure_runtime_dir
if exist "%RUNTIME_DIR%" exit /b 0
mkdir "%RUNTIME_DIR%" >nul 2>&1
if errorlevel 1 (
  call :log ERROR "Failed to create runtime directory: %RUNTIME_DIR%"
  exit /b 1
)
exit /b 0

:resolve_pid_by_title
set "%~2="
for /f "tokens=2 delims=," %%p in ('
  tasklist /v /fo csv /fi "imagename eq powershell.exe" ^| findstr /i /c:"%~1"
') do (
  set "%~2=%%~p"
  goto resolve_pid_done
)

:resolve_pid_done
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
  call :log INFO "Port %TARGET_PORT% LISTENING found (PID: %%p)."
  goto check_port_done
)

:check_port_done
set "%~2=%RESULT%"
exit /b 0

:init_log
if defined ADJUST_TOOL_LOG_FILE exit /b 0
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "LOG_TIMESTAMP=%%i"
if not defined LOG_TIMESTAMP (
  set "LOG_TIMESTAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
  set "LOG_TIMESTAMP=%LOG_TIMESTAMP: =0%"
)
set "ADJUST_TOOL_LOG_FILE=%CONTROL_LOG_DIR%\log_%LOG_TIMESTAMP%.txt"
powershell -NoProfile -Command "$p=$env:ADJUST_TOOL_LOG_FILE; Add-Content -Path $p -Value '[BOOT] start_adjust_tool created log file.' -Encoding utf8"
if errorlevel 1 (
  echo [FATAL] [start_adjust_tool] Failed to initialize log file: "%ADJUST_TOOL_LOG_FILE%".
  exit /b 1
)
exit /b 0

:log
set "LOG_LEVEL=%~1"
set "LOG_MESSAGE=%~2"
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "LOG_NOW=%%i"
if not defined LOG_NOW set "LOG_NOW=%DATE% %TIME%"
set "LOG_LINE=[%LOG_NOW%] [%LOG_LEVEL%] [start_adjust_tool] %LOG_MESSAGE%"
echo %LOG_LINE%
powershell -NoProfile -Command "$p=$env:ADJUST_TOOL_LOG_FILE; $line=$env:LOG_LINE; Add-Content -Path $p -Value $line -Encoding utf8"
if errorlevel 1 (
  echo [WARN] [start_adjust_tool] Failed to append log line.
)
set "LOG_NOW="
set "LOG_LEVEL="
set "LOG_MESSAGE="
set "LOG_LINE="
exit /b 0
