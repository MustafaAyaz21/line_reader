@echo off
chcp 65001 >nul
title Line Reader - Makale Yonetim Paneli
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
if errorlevel 1 (
  echo.
  echo Panel beklenmedik bir hata ile kapandi.
  pause
)
