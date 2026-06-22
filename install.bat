@echo off
chcp 65001 >nul 2>&1
title DNS Panel 一键安装

echo.
echo   DNS Panel 一键安装脚本
echo   正在启动 PowerShell 安装向导...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0install.ps1" %*

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo 安装失败，请检查上方错误信息。
    pause
)

echo.
pause
