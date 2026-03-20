@echo off
:: ClipSync Bridge - Silent Startup Launcher
:: Uses full Python path to avoid PATH issues at system startup

:: Check if already running by port
netstat -ano | findstr ":3456 " | findstr "LISTENING" >NUL 2>&1
if not errorlevel 1 (
    exit /b 0
)

:: Launch with full Python path, hidden
start "" /MIN "C:\Users\lowes\AppData\Local\Programs\Python\Python312\python.exe" "C:\Users\lowes\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\AI-HUB-v2\clipsync-bridge\sync_server.py"