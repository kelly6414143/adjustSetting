@echo off
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "CORE_DIR=%ROOT%\app"
set "PROXY_PORT=8787"
set "WEB_PORT=5500"
set "WEB_URL=http://localhost:%WEB_PORT%/index.html"
set "START_SCRIPT=%CORE_DIR%\start_adjust_tool.bat"
set "STOP_SCRIPT=%CORE_DIR%\stop_adjust_tool.bat"
set "INDEX_FILE=%CORE_DIR%\index.html"
set "RUN_ONCE=0"

cd /d "%ROOT%"
if errorlevel 1 (
  echo [FATAL] Failed to cd into "%ROOT%".
  exit /b 1
)
call :init_log
call :log INFO "adjust_tool_control started."
call :log INFO "Args: %*"

if not "%~1"=="" set "RUN_ONCE=1"
if /i "%~1"=="start" goto do_start
if /i "%~1"=="stop" goto do_stop
if /i "%~1"=="open" goto do_open
if /i "%~1"=="exit" goto do_exit

:menu
cls
echo ==========================================
echo        Adjust Tool Control Console
echo ==========================================
echo.
echo   1. start
echo   2. stop
echo   3. open
echo   0. exit
echo.
set /p "CHOICE=Choose (0-3): "

if "%CHOICE%"=="1" goto do_start
if "%CHOICE%"=="2" goto do_stop
if "%CHOICE%"=="3" goto do_open
if "%CHOICE%"=="0" goto do_exit

echo.
call :log ERROR "Invalid option. Expected 0-3."
call :wait_return
goto menu

:do_start
echo.
call :log INFO "Running start flow."
if not exist "%START_SCRIPT%" (
  call :log ERROR "Start script not found: %START_SCRIPT%"
  pause
  goto menu
)
call "%START_SCRIPT%"
set "LAST_CODE=%ERRORLEVEL%"
if not "%LAST_CODE%"=="0" (
  call :log ERROR "start script exited with code %LAST_CODE%."
)
call :log INFO "Start flow completed."
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_stop
echo.
call :log INFO "Running stop flow."
if not exist "%STOP_SCRIPT%" (
  call :log ERROR "Stop script not found: %STOP_SCRIPT%"
  pause
  goto menu
)
call "%STOP_SCRIPT%"
set "LAST_CODE=%ERRORLEVEL%"
if not "%LAST_CODE%"=="0" (
  call :log ERROR "stop script exited with code %LAST_CODE%."
)
call :log INFO "FINISH: stop flow completed."
echo [FINISH] stop completed.
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_open
echo.
call :log INFO "Running open flow."
call :check_port %PROXY_PORT% PROXY_STATUS
call :check_port %WEB_PORT% WEB_STATUS
if /i not "!PROXY_STATUS!"=="ON" (
  call :log WARN "Proxy is not running. Start script will run before open."
  if not exist "%START_SCRIPT%" (
    call :log ERROR "Start script not found: %START_SCRIPT%"
    pause
    goto menu
  )
  call "%START_SCRIPT%"
  set "LAST_CODE=!ERRORLEVEL!"
  if not "!LAST_CODE!"=="0" (
    call :log ERROR "start script exited with code !LAST_CODE! during open flow."
    pause
    goto menu
  )
) else if /i not "!WEB_STATUS!"=="ON" (
  call :log WARN "Web server is not running. Start script will run before open."
  if not exist "%START_SCRIPT%" (
    call :log ERROR "Start script not found: %START_SCRIPT%"
    pause
    goto menu
  )
  call "%START_SCRIPT%"
  set "LAST_CODE=!ERRORLEVEL!"
  if not "!LAST_CODE!"=="0" (
    call :log ERROR "start script exited with code !LAST_CODE! during open flow."
    pause
    goto menu
  )
)

start "" "%WEB_URL%"
if errorlevel 1 (
  call :log ERROR "Failed to open web url: %WEB_URL%"
)
call :log INFO "Web url opened: %WEB_URL%"
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:check_port
set "TARGET_PORT=%~1"
set "RESULT=OFF"
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%TARGET_PORT%" ^| findstr "LISTENING"') do (
  set "RESULT=ON"
  call :log INFO "Port %TARGET_PORT% LISTENING found (PID: %%p)."
  goto :check_port_done
)
:check_port_done
set "%~2=%RESULT%"
exit /b 0

:wait_for_port
set "TARGET_PORT=%~1"
set "MAX_RETRY=%~2"
set /a RETRY=0

:wait_for_port_loop
call :check_port %TARGET_PORT% PORT_STATUS
if /i "!PORT_STATUS!"=="ON" (
  set "%~3=ON"
  exit /b 0
)

set /a RETRY+=1
if !RETRY! GEQ %MAX_RETRY% (
  set "%~3=OFF"
  exit /b 0
)

timeout /t 1 >nul
if errorlevel 1 (
  call :log WARN "timeout command interrupted while waiting for port %TARGET_PORT%."
)
goto wait_for_port_loop

:wait_return
if /i "%ADJUST_TOOL_NON_INTERACTIVE%"=="1" exit /b 0
pause
exit /b 0

:do_exit
echo.
call :log INFO "Exit requested. Running stop flow before exit."
if exist "%STOP_SCRIPT%" (
  call "%STOP_SCRIPT%"
  set "LAST_CODE=%ERRORLEVEL%"
  if not "%LAST_CODE%"=="0" (
    call :log ERROR "stop script exited with code %LAST_CODE% during exit flow."
  ) else (
    call :log INFO "stop script completed during exit flow."
  )
) else (
  call :log WARN "Stop script not found during exit flow: %STOP_SCRIPT%"
)
call :log INFO "FINISH: control console exited."
echo [FINISH] exit completed.
exit /b 0

:init_log
if defined ADJUST_TOOL_LOG_FILE exit /b 0
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "LOG_TIMESTAMP=%%i"
if not defined LOG_TIMESTAMP (
  set "LOG_TIMESTAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
  set "LOG_TIMESTAMP=%LOG_TIMESTAMP: =0%"
)
set "ADJUST_TOOL_LOG_FILE=%ROOT%\log_%LOG_TIMESTAMP%.txt"
> "%ADJUST_TOOL_LOG_FILE%" echo ==================================================
>> "%ADJUST_TOOL_LOG_FILE%" echo Adjust Tool Log File
>> "%ADJUST_TOOL_LOG_FILE%" echo ==================================================
if errorlevel 1 (
  echo [FATAL] Failed to create log file at "%ADJUST_TOOL_LOG_FILE%".
  exit /b 1
)
echo [LOG] %ADJUST_TOOL_LOG_FILE%
exit /b 0

:log
set "LOG_LEVEL=%~1"
set "LOG_MESSAGE=%~2"
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "LOG_NOW=%%i"
if not defined LOG_NOW set "LOG_NOW=%DATE% %TIME%"
set "LOG_LINE=[%LOG_NOW%] [%LOG_LEVEL%] %LOG_MESSAGE%"
echo %LOG_LINE%
>> "%ADJUST_TOOL_LOG_FILE%" echo %LOG_LINE%
set "LOG_NOW="
set "LOG_LEVEL="
set "LOG_MESSAGE="
set "LOG_LINE="
exit /b 0
