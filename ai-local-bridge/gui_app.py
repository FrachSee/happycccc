#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ai-local-bridge 图形界面(GUI)
================================
在 server.py(纯标准库的文件桥接服务)之上套一层 tkinter 窗口:
  1. 选择允许 AI 访问的文件夹;
  2. 一键「启动桥接」= 启动本机服务 + 启动 cloudflared 隧道;
  3. 实时显示运行状态 / 本机地址 / 公网地址 / 访问令牌;
  4. 底部自动生成发给云端 AI 的「话术」,一键复制。

仍然只依赖 Python 标准库(tkinter 随官方安装包自带),
cloudflared.exe 需用户自行放在本程序同目录(见 README)。
可用 PyInstaller 打包成独立 EXE(见 build_exe.bat)。
"""

import json
import os
import re
import secrets
import subprocess
import sys
import threading
from http.server import ThreadingHTTPServer

import tkinter as tk
from tkinter import filedialog, messagebox

import server  # 复用 server.py 里的 Handler(鉴权、路径防护、备份等安全逻辑)

# PyInstaller --windowed 模式下没有控制台,stdout/stderr 为 None,
# 而 server.py 里有 print 日志,这里重定向到空设备防止报错。
if sys.stdout is None:
    sys.stdout = open(os.devnull, "w")
if sys.stderr is None:
    sys.stderr = open(os.devnull, "w")


def app_dir():
    """配置文件/cloudflared 的查找目录:打包后取 EXE 所在目录,源码运行取脚本目录。"""
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.executable)
    return os.path.dirname(os.path.abspath(__file__))


CONFIG_FILE = os.path.join(app_dir(), "config.json")
TUNNEL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")


def load_config():
    """读取 config.json,不存在或缺项时用默认值补齐。"""
    cfg = dict(server.DEFAULT_CONFIG)
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg.update(json.load(f))
        except ValueError:
            pass  # 配置损坏时按首次运行处理
    return cfg


def save_config(cfg):
    with open(CONFIG_FILE, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def find_cloudflared():
    """优先用程序同目录下的 cloudflared(.exe),其次找系统 PATH。找不到返回 None。"""
    for name in ("cloudflared.exe", "cloudflared"):
        p = os.path.join(app_dir(), name)
        if os.path.isfile(p):
            return p
    import shutil
    return shutil.which("cloudflared")


def build_prompt(url, token, root):
    """生成发给云端 AI 的中文话术。"""
    return (
        "【本机桥接已开启】\n"
        f"桥接地址：{url}\n"
        f"认证：Authorization: Bearer {token}\n"
        f"工作区根目录：{root}\n"
        "API（所有请求都必须带上面的认证请求头，path 为根目录内的相对路径）：\n"
        "- GET  /api/health                查看状态\n"
        "- GET  /api/files?path=相对路径    列目录 / 读文件\n"
        '- PUT  /api/files?path=相对路径    写入文件（请求体为原始内容，或 JSON {"content":"..."}）\n'
        "- POST /api/files/mkdir?path=相对路径  创建目录\n"
        "请通过此桥接读写我本机文件。例如：请把 xxx.md 写到当前目录（PUT /api/files?path=xxx.md）。\n"
    )


class BridgeGUI:
    def __init__(self, root):
        self.root = root
        self.httpd = None          # ThreadingHTTPServer 实例(运行中才有)
        self.tunnel_proc = None    # cloudflared 子进程
        self.tunnel_url = None
        self.cfg = load_config()

        root.title("AI 本机桥接 (ai-local-bridge)")
        root.geometry("640x560")
        root.protocol("WM_DELETE_WINDOW", self.on_close)
        pad = {"padx": 10, "pady": 4}

        # --- 第一行:文件夹选择 ---
        row1 = tk.Frame(root); row1.pack(fill="x", **pad)
        tk.Label(row1, text="允许 AI 访问的文件夹:").pack(side="left")
        self.dir_var = tk.StringVar(value=self.cfg.get("root_dir", ""))
        tk.Entry(row1, textvariable=self.dir_var).pack(side="left", fill="x", expand=True, padx=6)
        tk.Button(row1, text="浏览…", command=self.pick_dir).pack(side="left")

        # --- 第二行:启动/停止按钮 ---
        row2 = tk.Frame(root); row2.pack(fill="x", **pad)
        self.start_btn = tk.Button(row2, text="启动桥接", width=14, bg="#2e7d32",
                                   fg="white", command=self.start_bridge)
        self.start_btn.pack(side="left")
        self.stop_btn = tk.Button(row2, text="停止桥接", width=14, state="disabled",
                                  command=self.stop_bridge)
        self.stop_btn.pack(side="left", padx=8)

        # --- 状态区 ---
        box = tk.LabelFrame(root, text="运行状态"); box.pack(fill="x", **pad)
        self.status_var = tk.StringVar(value="● 未启动")
        self.local_var = tk.StringVar(value="-")
        self.public_var = tk.StringVar(value="-")
        self.token_var = tk.StringVar(value="-")
        for label, var in (("状态", self.status_var), ("本机地址", self.local_var),
                           ("公网地址", self.public_var), ("访问令牌", self.token_var)):
            r = tk.Frame(box); r.pack(fill="x", padx=8, pady=2)
            tk.Label(r, text=label + ":", width=8, anchor="w").pack(side="left")
            tk.Label(r, textvariable=var, anchor="w", fg="#1a237e",
                     wraplength=500, justify="left").pack(side="left", fill="x")

        # --- 话术区 ---
        row3 = tk.Frame(root); row3.pack(fill="x", **pad)
        tk.Label(row3, text="发给云端 AI 的话术(启动并连上隧道后自动生成):").pack(side="left")
        tk.Button(row3, text="复制话术", command=self.copy_prompt).pack(side="right")
        self.prompt_text = tk.Text(root, height=12, wrap="word", state="disabled",
                                   bg="#f5f5f5")
        self.prompt_text.pack(fill="both", expand=True, padx=10, pady=(0, 10))

    # ---------- 界面小工具 ----------
    def pick_dir(self):
        d = filedialog.askdirectory(title="选择允许 AI 访问的文件夹")
        if d:
            self.dir_var.set(d)

    def set_prompt(self, text):
        self.prompt_text.config(state="normal")
        self.prompt_text.delete("1.0", "end")
        self.prompt_text.insert("1.0", text)
        self.prompt_text.config(state="disabled")

    def copy_prompt(self):
        text = self.prompt_text.get("1.0", "end").strip()
        if not text:
            messagebox.showinfo("提示", "还没有话术可复制,请先启动桥接。")
            return
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        messagebox.showinfo("已复制", "话术已复制到剪贴板,直接粘贴发给云端 AI 即可。")

    # ---------- 启动 / 停止 ----------
    def start_bridge(self):
        root_dir = self.dir_var.get().strip()
        if not root_dir or not os.path.isdir(root_dir):
            messagebox.showerror("错误", "请先选择一个存在的文件夹。")
            return

        # 组装配置并持久化(token 只生成一次,重启不变)
        self.cfg["root_dir"] = root_dir
        if not self.cfg.get("token"):
            self.cfg["token"] = secrets.token_urlsafe(32)
        save_config(self.cfg)

        # 注入配置到 server 模块并在后台线程启动 HTTP 服务
        server.CFG = dict(self.cfg, root_dir=os.path.realpath(root_dir))
        host, port = self.cfg["host"], int(self.cfg["port"])
        try:
            self.httpd = ThreadingHTTPServer((host, port), server.Handler)
        except OSError as e:
            messagebox.showerror("错误", f"端口 {port} 启动失败(可能被占用):{e}")
            return
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

        local_url = f"http://{host}:{port}"
        self.status_var.set("● 运行中")
        self.local_var.set(local_url)
        self.token_var.set(self.cfg["token"])
        self.start_btn.config(state="disabled")
        self.stop_btn.config(state="normal")

        # 启动 cloudflared 隧道(找不到则提示手动处理,本机服务照常可用)
        cf = find_cloudflared()
        if cf:
            self.public_var.set("正在建立隧道,请稍候…")
            self.set_prompt("正在等待 cloudflared 隧道就绪,拿到公网地址后这里会自动生成话术…")
            flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
            self.tunnel_proc = subprocess.Popen(
                [cf, "tunnel", "--url", local_url],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", creationflags=flags)
            threading.Thread(target=self._watch_tunnel, daemon=True).start()
        else:
            self.public_var.set("未找到 cloudflared.exe(请放到本程序同目录后重启桥接)")
            # 没有隧道时仍给出本机地址话术,方便局域网/自备转发的用户
            self.set_prompt(build_prompt(local_url + "(仅本机可访问,公网使用请配置 cloudflared)",
                                         self.cfg["token"], root_dir))

    def _watch_tunnel(self):
        """后台线程:逐行读 cloudflared 输出,抓取 trycloudflare 公网地址。"""
        for line in self.tunnel_proc.stdout:
            m = TUNNEL_RE.search(line)
            if m and not self.tunnel_url:
                url = m.group(0)
                # tkinter 非线程安全,必须回到主线程更新界面
                self.root.after(0, self._on_tunnel_ready, url)
            # 继续读完所有输出,避免子进程因管道写满而卡死

    def _on_tunnel_ready(self, url):
        self.tunnel_url = url
        self.public_var.set(url)
        self.set_prompt(build_prompt(url, self.cfg["token"], self.dir_var.get().strip()))

    def stop_bridge(self):
        if self.tunnel_proc:
            self.tunnel_proc.terminate()
            self.tunnel_proc = None
        if self.httpd:
            threading.Thread(target=self.httpd.shutdown, daemon=True).start()
            self.httpd = None
        self.tunnel_url = None
        self.status_var.set("● 已停止")
        self.local_var.set("-")
        self.public_var.set("-")
        self.start_btn.config(state="normal")
        self.stop_btn.config(state="disabled")
        self.set_prompt("桥接已停止,外网已无法访问你的电脑。")

    def on_close(self):
        self.stop_bridge()
        self.root.destroy()


def main():
    root = tk.Tk()
    BridgeGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
