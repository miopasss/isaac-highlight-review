@echo off
REM ===========================================================================
REM 双击这个 = 先备份存档，再启动游戏，退出后自动再备份一次
REM 必须放在 tools\ 目录下（和 play.ps1 同级）
REM ===========================================================================
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1"
if errorlevel 1 pause
