@echo off
rem ============================================================
rem cloudflared 快速隧道启动脚本
rem 前提:已双击 start.bat 启动本机服务(默认端口 8787)
rem 作用:把 https://xxxx.trycloudflare.com 转发到本机 127.0.0.1:8787
rem ============================================================
chcp 65001 >nul
cd /d "%~dp0"

rem 优先使用放在本目录下的 cloudflared.exe,其次使用系统 PATH 里的
set CF=cloudflared.exe
if not exist "%CF%" (
    where cloudflared >nul 2>nul
    if errorlevel 1 (
        echo [错误] 未找到 cloudflared。请到下面地址下载 Windows 64 位版:
        echo   https://github.com/cloudflare/cloudflared/releases/latest
        echo   下载 cloudflared-windows-amd64.exe,改名为 cloudflared.exe,
        echo   放到本文件夹后再次双击本脚本。
        pause
        exit /b 1
    )
    set CF=cloudflared
)

echo 正在建立隧道...成功后会显示一行 https://xxxx.trycloudflare.com
echo 把这个网址 + config.json 里的 token 一起发给 AI 即可。
echo (关闭本窗口即断开隧道;每次重开网址会变化)
"%CF%" tunnel --url http://127.0.0.1:8787
pause
