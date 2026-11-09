@echo off
chcp 65001 >nul
wscript.exe "%~dp0launcher\start.vbs" %*
