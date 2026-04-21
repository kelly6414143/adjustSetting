@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "PROXY_PORT=8787"
set "WEB_PORT=5500"
set "CONTROL_LOG_DIR=%~dp0.."
set "RUNTIME_DIR=%~dp0.runtime"
set "PROXY_PID_FILE=%RUNTIME_DIR%\proxy.pid"
set "WEB_PID_FILE=%RUNTIME_DIR%\web.pid"

cd /d "%~dp0"
if errorlevel 1 (
  echo [FATAL] [stop_adjust_tool] Failed to cd into "%~dp0".
  exit /b 1
)
call :init_log
call :log INFO "stop_adjust_tool started."
call :log INFO "Args: %*"

call :kill_by_pid_file "%PROXY_PID_FILE%" "proxy-pid-file"
call :kill_by_pid_file "%WEB_PID_FILE%" "web-pid-file"
call :kill_by_port %PROXY_PORT% "Proxy"
call :kill_by_port %WEB_PORT% "Web"
call :log INFO "WAIT: closing windows by title filter."
call :kill_by_windowtitle_taskkill "Adjust Proxy"
call :kill_by_windowtitle_taskkill "Adjust Web"
call :log INFO "WAIT: scanning commandline match (this may take several seconds)."
call :close_by_commandline "powershell.exe" "proxy.ps1"
call :close_by_commandline "pwsh.exe" "proxy.ps1"
call :close_by_commandline "powershell.exe" "web_server.ps1"
call :close_by_commandline "pwsh.exe" "web_server.ps1"

call :log INFO "FINISH: stop process check completed."
exit /b 0

:kill_by_windowtitle_taskkill
set "TITLE=%~1"
taskkill /FI "WINDOWTITLE eq %TITLE%*" /F /T >nul 2>&1
if errorlevel 1 (
  call :log INFO "No process killed by taskkill windowtitle filter: %TITLE%."
) else (
  call :log INFO "taskkill windowtitle filter executed for: %TITLE%."
)
exit /b 0

:kill_by_pid_file
set "PID_FILE=%~1"
set "DESC=%~2"
if not exist "%PID_FILE%" (
  call :log INFO "PID file not found: %PID_FILE%"
  exit /b 0
)

set "FILE_PID="
for /f "usebackq tokens=1 delims= " %%p in ("%PID_FILE%") do (
  set "FILE_PID=%%p"
  goto pid_file_read_done
)

:pid_file_read_done
if not defined FILE_PID (
  call :log WARN "PID file is empty: %PID_FILE%"
  del /f /q "%PID_FILE%" >nul 2>&1
  exit /b 0
)

echo !FILE_PID! | findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
  call :log WARN "PID file contains non-numeric value (!FILE_PID!): %PID_FILE%"
  del /f /q "%PID_FILE%" >nul 2>&1
  exit /b 0
)

call :log INFO "Closing PID !FILE_PID! from %DESC%."
call :force_kill_pid !FILE_PID! %DESC%
del /f /q "%PID_FILE%" >nul 2>&1
if errorlevel 1 (
  call :log WARN "Failed to delete PID file: %PID_FILE%"
)

exit /b 0

:kill_by_port
set "PORT=%~1"
set "NAME=%~2"
set "FOUND=0"
set "SEEN_PIDS=,"

for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PORT%" ^| findstr "LISTENING"') do (
  set "PID=%%p"
  echo !SEEN_PIDS! | find ",!PID!," >nul
  if errorlevel 1 (
    set "FOUND=1"
    set "SEEN_PIDS=!SEEN_PIDS!!PID!,"
    call :log INFO "Stopping !NAME! process on port !PORT! (PID: !PID!)."
    call :force_kill_pid !PID! port-process
  )
)

if "!FOUND!"=="0" (
  call :log INFO "No LISTENING process on port !PORT!."
)

exit /b 0

:close_window_by_title
set "TITLE=%~1"
set "IMAGE=%~2"
if "%IMAGE%"=="" set "IMAGE=cmd.exe"
set "CLOSED=0"

for /f "tokens=2 delims=," %%p in ('
  tasklist /v /fo csv /fi "imagename eq %IMAGE%" ^| findstr /i /c:"%TITLE%"
') do (
  set "PID=%%~p"
  set "CLOSED=1"
  call :log INFO "Closing terminal window %TITLE% (%IMAGE%) (PID: !PID!)."
  call :force_kill_pid !PID! title-window
)

if "!CLOSED!"=="0" (
  call :log INFO "No terminal window found for %TITLE%."
)

exit /b 0

:close_by_commandline
set "IMAGE=%~1"
set "KEYWORD=%~2"
set "CLOSED=0"
call :log INFO "WAIT: query %IMAGE% by keyword %KEYWORD%."

for /f %%p in ('
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$img='%IMAGE%'; $kw='%KEYWORD%'; $procs=Get-CimInstance Win32_Process; foreach($p in $procs){ if($p.Name -ieq $img -and $p.CommandLine -and $p.CommandLine.ToLower().Contains($kw.ToLower())){ $p.ProcessId } }"
') do (
  set "PID=%%p"
  set "CLOSED=1"
  call :log INFO "Closing by commandline %KEYWORD% (%IMAGE%) (PID: !PID!)."
  call :force_kill_pid !PID! commandline-match
)
if errorlevel 1 (
  call :log WARN "Process query failed for image=%IMAGE% keyword=%KEYWORD%."
)

if "!CLOSED!"=="0" (
  call :log INFO "No %IMAGE% process found by commandline %KEYWORD%."
)

exit /b 0

:force_kill_pid
set "TARGET_PID=%~1"
set "TARGET_DESC=%~2"

taskkill /PID %TARGET_PID% /T /F >nul 2>&1
if errorlevel 1 (
  call :log WARN "taskkill failed for PID %TARGET_PID%, trying Stop-Process fallback."
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Stop-Process -Id %TARGET_PID% -Force -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
  if errorlevel 1 (
    call :log WARN "Stop-Process fallback also failed for PID %TARGET_PID%."
  )
)

tasklist /fi "PID eq %TARGET_PID%" 2>nul | find "%TARGET_PID%" >nul
if errorlevel 1 (
  call :log INFO "Closed PID %TARGET_PID% for %TARGET_DESC%."
) else (
  call :log WARN "Failed to close PID %TARGET_PID% for %TARGET_DESC%."
)

exit /b 0

:init_log
if defined ADJUST_TOOL_LOG_FILE exit /b 0
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "LOG_TIMESTAMP=%%i"
if not defined LOG_TIMESTAMP (
  set "LOG_TIMESTAMP=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
  set "LOG_TIMESTAMP=!LOG_TIMESTAMP: =0!"
)
set "ADJUST_TOOL_LOG_FILE=%CONTROL_LOG_DIR%\log_%LOG_TIMESTAMP%.txt"
powershell -NoProfile -Command "$p=$env:ADJUST_TOOL_LOG_FILE; Add-Content -Path $p -Value '[BOOT] stop_adjust_tool created log file.' -Encoding utf8"
if errorlevel 1 (
  echo [FATAL] [stop_adjust_tool] Failed to initialize log file: "%ADJUST_TOOL_LOG_FILE%".
  exit /b 1
)
exit /b 0

:log
set "LOG_LEVEL=%~1"
set "LOG_MESSAGE=%~2"
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd HH:mm:ss'"') do set "LOG_NOW=%%i"
if not defined LOG_NOW set "LOG_NOW=%DATE% %TIME%"
set "LOG_LINE=[!LOG_NOW!] [!LOG_LEVEL!] [stop_adjust_tool] !LOG_MESSAGE!"
echo !LOG_LINE!
powershell -NoProfile -Command "$p=$env:ADJUST_TOOL_LOG_FILE; $line=$env:LOG_LINE; Add-Content -Path $p -Value $line -Encoding utf8"
if errorlevel 1 (
  echo [WARN] [stop_adjust_tool] Failed to append log line.
)
set "LOG_NOW="
set "LOG_LEVEL="
set "LOG_MESSAGE="
set "LOG_LINE="
exit /b 0
