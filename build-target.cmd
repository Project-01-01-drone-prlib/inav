@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-target.ps1" %*
