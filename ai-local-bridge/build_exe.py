#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用 PyInstaller 把 gui_app.py 打包成独立 Windows 程序。
请在 Windows 上运行(PyInstaller 不支持跨系统打包),
推荐直接双击 build_exe.bat,它会自动安装 PyInstaller 并调用本脚本。

采用 --onedir 模式(对 tkinter 兼容性最好、启动快),
产物在 dist/AIBridge/,主程序为 dist/AIBridge/AIBridge.exe。
"""
import PyInstaller.__main__

PyInstaller.__main__.run([
    "gui_app.py",
    "--name=AIBridge",
    "--onedir",       # 单文件夹模式,tkinter 打包最稳定
    "--windowed",     # 不弹出黑色控制台窗口
    "--noconfirm",    # 覆盖旧产物不询问
    "--clean",
])

print()
print("=" * 60)
print("打包完成!")
print(r"程序在 dist\AIBridge\ 文件夹里,主程序是 AIBridge.exe。")
print(r"请把 cloudflared.exe 也复制进 dist\AIBridge\,与 AIBridge.exe 并排。")
print("整个 AIBridge 文件夹可以拷到任何 Windows 电脑上直接使用。")
print("=" * 60)
