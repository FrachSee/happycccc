@echo off
rem ============================================================
rem ai-local-bridge 启动脚本(Windows)
rem 双击即可:检查 Python -> 启动本机桥接服务(无需安装任何第三方库)
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

if not exist config.json (
    echo 首次运行:将根据 config.example.json 生成 config.json ...
    copy config.example.json config.json >nul
    echo 请用记事本打开 config.json,把 root_dir 改成你允许 AI 访问的文件夹,
    echo 例如 "D:/剧本",保存后再次双击本脚本。
    pause
    exit /b 0
)

echo 正在启动 ai-local-bridge(关闭本窗口即停止服务)...
echo 提示:启动成功后,另开一个窗口双击 start_tunnel.bat 获取公网地址。
python server.py
pause
