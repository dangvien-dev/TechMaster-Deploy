@echo off
rem TechMaster Deploy over the LAN: copy the program from this share to C:\TechMaster-Deploy,
rem check every file, then open it as administrator. Open this file from \\COMPUTER\TechMaster$\App.
cls
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Network.Launch.ps1"
