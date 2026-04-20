@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "CORE_DIR=%ROOT%\app"
set "PROXY_PORT=8787"
set "WEB_PORT=5500"
set "START_SCRIPT=%CORE_DIR%\start_adjust_tool.bat"
set "STOP_SCRIPT=%CORE_DIR%\stop_adjust_tool.bat"
set "WEB_URL=http://localhost:%WEB_PORT%/index.html"
set "RUN_ONCE=0"

cd /d "%ROOT%"

if not "%~1"=="" set "RUN_ONCE=1"
if /i "%~1"=="start" goto do_start
if /i "%~1"=="stop" goto do_stop
if /i "%~1"=="restart" goto do_restart
if /i "%~1"=="status" goto do_status
if /i "%~1"=="open" goto do_open
if /i "%~1"=="exit" goto do_exit

:menu
cls
echo(==========================================
echo(       Adjust Tool 單一入口控制台
echo(==========================================
echo(
echo  1. 啟動工具
echo  2. 停止工具
echo  3. 重啟工具
echo  4. 查看狀態
echo  5. Open Web
echo  0. 離開
echo(
set /p "CHOICE=請輸入選項 (0-5): "

if "%CHOICE%"=="1" goto do_start
if "%CHOICE%"=="2" goto do_stop
if "%CHOICE%"=="3" goto do_restart
if "%CHOICE%"=="4" goto do_status
if "%CHOICE%"=="5" goto do_open
if "%CHOICE%"=="0" goto do_exit

echo.
echo [錯誤] 無效選項，請輸入 0-5。
call :wait_return
goto menu

:do_start
echo.
echo [執行] 啟動工具中...
if not exist "%CORE_DIR%" (
  echo [錯誤] 找不到核心資料夾：%CORE_DIR%
  pause
  goto menu
)
if not exist "%START_SCRIPT%" (
  echo [錯誤] 找不到啟動腳本：%START_SCRIPT%
  pause
  goto menu
)
call "%START_SCRIPT%"
echo.
echo [完成] 啟動流程已執行。
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_stop
echo.
echo [執行] 停止工具中...
if not exist "%CORE_DIR%" (
  echo [錯誤] 找不到核心資料夾：%CORE_DIR%
  pause
  goto menu
)
if not exist "%STOP_SCRIPT%" (
  echo [錯誤] 找不到停止腳本：%STOP_SCRIPT%
  pause
  goto menu
)
call "%STOP_SCRIPT%"
echo.
echo [完成] 停止流程已執行。
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_restart
echo.
echo [執行] 重啟工具中（先停止再啟動）...
if not exist "%CORE_DIR%" (
  echo [錯誤] 找不到核心資料夾：%CORE_DIR%
  pause
  goto menu
)
if not exist "%STOP_SCRIPT%" (
  echo [錯誤] 找不到停止腳本：%STOP_SCRIPT%
  pause
  goto menu
)
if not exist "%START_SCRIPT%" (
  echo [錯誤] 找不到啟動腳本：%START_SCRIPT%
  pause
  goto menu
)
call "%STOP_SCRIPT%"
call "%START_SCRIPT%"
echo.
echo [完成] 重啟流程已執行。
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_status
echo.
call :check_port %PROXY_PORT% PROXY_STATUS
call :check_port %WEB_PORT% WEB_STATUS

if "!PROXY_STATUS!"=="ON" (
  echo [狀態] 代理服務：已啟動（%PROXY_PORT%）
) else (
  echo [狀態] 代理服務：未啟動（%PROXY_PORT%）
)

if "!WEB_STATUS!"=="ON" (
  echo [狀態] 網頁服務：已啟動（%WEB_PORT%）
) else (
  echo [狀態] 網頁服務：未啟動（%WEB_PORT%）
)

call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:do_open
echo.
call :check_port %WEB_PORT% WEB_STATUS
if "!WEB_STATUS!"=="ON" (
  echo [執行] 開啟網頁：%WEB_URL%
  start "" "%WEB_URL%"
  echo [完成] 已送出開啟指令。
) else (
  echo [提示] 網頁服務尚未啟動（%WEB_PORT%），請先選擇選項 1 啟動工具。
)
call :wait_return
if "%RUN_ONCE%"=="1" goto do_exit
goto menu

:check_port
set "TARGET_PORT=%~1"
set "RESULT=OFF"
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%TARGET_PORT%" ^| findstr "LISTENING"') do (
  set "RESULT=ON"
  goto :check_port_done
)
:check_port_done
set "%~2=%RESULT%"
exit /b 0

:wait_return
if /i "%ADJUST_TOOL_NON_INTERACTIVE%"=="1" exit /b 0
pause
exit /b 0

:do_exit
echo.
echo [完成] 已離開控制台。
exit /b 0
