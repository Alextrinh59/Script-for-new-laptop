@echo off
setlocal EnableExtensions
title Kiem Tra May Moi
chcp 65001 >nul
cd /d "%~dp0"

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "ROOT=%~dp0"
set "SELF=%~f0"

rem Kiem tra quyen Administrator. Neu chua co, tu mo lai bang UAC.
"%SystemRoot%\System32\fltmc.exe" >nul 2>&1
if not errorlevel 1 goto run

echo.
echo ============================================================
echo   KIEM TRA MAY MOI - CAN QUYEN ADMINISTRATOR
echo ============================================================
echo Dang mo lai voi quyen Administrator...
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { Start-Process -FilePath $env:SELF -WorkingDirectory $env:ROOT -Verb RunAs -ErrorAction Stop } catch { exit 1 }"
if not errorlevel 1 goto end

echo.
echo Khong the nang quyen.
echo Hay chuot phai file BAT va chon "Run as administrator",
echo hoac mo PowerShell bang quyen Administrator roi chay lai.
echo.
pause
goto end

:run
if not exist "%ROOT%KiemTraMayMoi.ps1" goto missing

echo ============================================================
echo   KIEM TRA MAY MOI - DANG CHAY VOI QUYEN ADMINISTRATOR
echo ============================================================
echo.

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%KiemTraMayMoi.ps1"
set "EXITCODE=%errorlevel%"

if "%EXITCODE%"=="0" goto end
echo.
echo Script ket thuc voi ma loi %EXITCODE%.
pause
exit /b %EXITCODE%

:missing
echo.
echo Khong tim thay file KiemTraMayMoi.ps1 trong cung thu muc.
echo.
pause
exit /b 1

:end
exit /b 0
