@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "PROXY_PORT=8787"
set "WEB_PORT=5500"

call :kill_by_port %PROXY_PORT% "Proxy"
call :kill_by_port %WEB_PORT% "Web"
call :close_window_by_title "Adjust Proxy"
call :close_window_by_title "Adjust Web"

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
    taskkill /PID !PID! /F >nul 2>&1
    if errorlevel 1 (
      echo [WARN] Failed to stop PID !PID! on port !PORT!.
    ) else (
      echo [OK] Stopped PID !PID! on port !PORT!.
    )
  )
)

if "!FOUND!"=="0" (
  echo [INFO] No LISTENING process on port !PORT!.
)

exit /b 0

:close_window_by_title
set "TITLE=%~1"
set "CLOSED=0"

for /f "tokens=2 delims=," %%p in ('
  tasklist /v /fo csv /fi "imagename eq cmd.exe" ^| findstr /i /c:"%TITLE%"
') do (
  set "PID=%%~p"
  set "CLOSED=1"
  echo [INFO] Closing terminal window "%TITLE%" ^(PID: !PID!^)
  taskkill /PID !PID! /T /F >nul 2>&1
  if errorlevel 1 (
    echo [WARN] Failed to close terminal PID !PID!.
  ) else (
    echo [OK] Closed terminal PID !PID!.
  )
)

if "!CLOSED!"=="0" (
  echo [INFO] No terminal window found for "%TITLE%".
)

exit /b 0
