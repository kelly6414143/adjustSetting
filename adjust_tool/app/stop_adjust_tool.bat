@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "PROXY_PORT=8787"
set "WEB_PORT=5500"

call :kill_by_port %PROXY_PORT% "Proxy"
call :kill_by_port %WEB_PORT% "Web"
call :close_window_by_title "Adjust Proxy" "cmd.exe"
call :close_window_by_title "Adjust Proxy" "powershell.exe"
call :close_window_by_title "Adjust Proxy" "pwsh.exe"
call :close_window_by_title "Adjust Web" "cmd.exe"
call :close_by_commandline "powershell.exe" "proxy.ps1"
call :close_by_commandline "pwsh.exe" "proxy.ps1"
call :close_by_commandline "cmd.exe" "node proxy.js"
call :close_by_commandline "cmd.exe" "python -m http.server %WEB_PORT%"

echo [DONE] Stop process check completed.
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
    echo [INFO] Stopping !NAME! process on port !PORT! ^(PID: !PID!^)
    call :force_kill_pid !PID! port-process
  )
)

if "!FOUND!"=="0" (
  echo [INFO] No LISTENING process on port !PORT!.
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
  echo [INFO] Closing terminal window "%TITLE%" ^(%IMAGE%^) ^(PID: !PID!^)
  call :force_kill_pid !PID! title-window
)

if "!CLOSED!"=="0" (
  echo [INFO] No terminal window found for "%TITLE%".
)

exit /b 0

:close_by_commandline
set "IMAGE=%~1"
set "KEYWORD=%~2"
set "CLOSED=0"

for /f %%p in ('
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$img='%IMAGE%'; $kw='%KEYWORD%'; $procs=Get-CimInstance Win32_Process; foreach($p in $procs){ if($p.Name -ieq $img -and $p.CommandLine -and $p.CommandLine.ToLower().Contains($kw.ToLower())){ $p.ProcessId } }"
') do (
  set "PID=%%p"
  set "CLOSED=1"
  echo [INFO] Closing by commandline "%KEYWORD%" ^(%IMAGE%^) ^(PID: !PID!^)
  call :force_kill_pid !PID! commandline-match
)

if "!CLOSED!"=="0" (
  echo [INFO] No %IMAGE% process found by commandline "%KEYWORD%".
)

exit /b 0

:force_kill_pid
set "TARGET_PID=%~1"
set "TARGET_DESC=%~2"

taskkill /PID %TARGET_PID% /T /F >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Stop-Process -Id %TARGET_PID% -Force -ErrorAction Stop } catch { exit 1 }" >nul 2>&1
)

tasklist /fi "PID eq %TARGET_PID%" 2>nul | find "%TARGET_PID%" >nul
if errorlevel 1 (
  echo [OK] Closed PID %TARGET_PID% for %TARGET_DESC%.
) else (
  echo [WARN] Failed to close PID %TARGET_PID% for %TARGET_DESC%.
)

exit /b 0
