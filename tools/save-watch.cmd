@echo off
rem ---------------------------------------------------------------------------
rem  save-watch.cmd -- open the visible backup window.
rem  ASCII only: cmd reads this file with the OEM/ANSI code page, so no Chinese.
rem ---------------------------------------------------------------------------
chcp 65001 >nul
title Isaac Save Watch
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0save-watch.ps1" %*
echo.
echo [watcher stopped] press any key to close this window
pause >nul
