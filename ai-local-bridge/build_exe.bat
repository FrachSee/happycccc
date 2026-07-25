@echo off
rem ============================================================
rem 一键打包脚本:把图形界面打包成独立 EXE(需在 Windows 上运行)
rem 产物:dist\AIBridge\AIBridge.exe
rem ============================================================
chcp 65001 >nul
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
    echo [错误] 未检测到 Python,请先到 https://www.python.org/downloads/ 安装
    echo        安装时务必勾选 "Add Python to PATH"
    pause
    exit /b 1
)

echo [1/2] 安装打包工具 PyInstaller ...
python -m pip install --upgrade pyinstaller
if errorlevel 1 (
    echo [错误] PyInstaller 安装失败,请检查网络后重试。
    pause
    exit /b 1
)

echo [2/2] 开始打包(约 1-2 分钟)...
python build_exe.py
if errorlevel 1 (
    echo [错误] 打包失败,请把上面的报错信息截图反馈。
    pause
    exit /b 1
)

rem 如果本目录已有 cloudflared.exe,顺手复制到产物文件夹
if exist cloudflared.exe (
    copy /y cloudflared.exe dist\AIBridge\cloudflared.exe >nul
    echo 已把 cloudflared.exe 复制到 dist\AIBridge\ 。
)

echo.
echo 完成!双击 dist\AIBridge\AIBridge.exe 即可使用。
pause
