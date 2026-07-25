#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ai-local-bridge —— 自有可审计的本机文件桥接服务
=================================================
用途:在你自己的电脑上开一个极小的 HTTP 接口,让云端 AI(经由你自己启动的
cloudflared 隧道)读写【指定文件夹】里的文件。全部代码就这一个文件,
只用 Python 标准库,无任何第三方依赖、无遥测、不主动连接任何外部服务器。

安全设计(请自行审计,共 ~300 行):
  1. 只暴露 config.json 里 root_dir 指定的文件夹,路径穿越(.. / 绝对路径)一律拒绝;
  2. 所有接口都要求 Authorization: Bearer <token>,token 首次运行自动生成并存入 config.json;
  3. 可选只读模式(read_only=true 时禁止写入/建目录);
  4. 覆盖已有文件前自动备份到 root_dir/.ai-bridge-backup/;
  5. 默认只监听 127.0.0.1,外网访问必须由你自己运行 cloudflared 转发。
"""

import json
import mimetypes
import os
import secrets
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ---------- 常量 ----------
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")
BACKUP_DIR_NAME = ".ai-bridge-backup"   # 备份目录(位于 root_dir 内)
MAX_BODY = 20 * 1024 * 1024             # 单次写入上限 20MB,防止恶意灌满磁盘
TEXT_EXTS = {".md", ".txt", ".json", ".csv", ".yml", ".yaml", ".html", ".css",
             ".js", ".py", ".xml", ".ini", ".log", ".srt", ".bat"}

DEFAULT_CONFIG = {
    "root_dir": "",          # 必填:允许访问的文件夹,例如 "D:/剧本"
    "port": 8787,            # 本机监听端口
    "host": "127.0.0.1",     # 默认只监听本机,请勿改成 0.0.0.0 除非你明白后果
    "token": "",             # 留空则首次启动自动生成
    "read_only": False       # true = 只读模式,禁止一切写操作
}


# ---------- 配置加载 ----------
def load_config():
    """读取 config.json;不存在则生成模板并退出提示用户填写 root_dir。"""
    if not os.path.exists(CONFIG_FILE):
        cfg = dict(DEFAULT_CONFIG)
        cfg["token"] = secrets.token_urlsafe(32)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
        print("已生成配置文件 config.json,请先编辑其中的 root_dir(允许访问的文件夹),再重新启动。")
        sys.exit(1)

    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        cfg = {**DEFAULT_CONFIG, **json.load(f)}

    # token 为空则自动生成一个高强度随机 token 并写回
    if not cfg["token"]:
        cfg["token"] = secrets.token_urlsafe(32)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)

    if not cfg["root_dir"]:
        print("错误:config.json 里的 root_dir 为空,请填写允许访问的文件夹路径,例如 D:/剧本")
        sys.exit(1)
    root = os.path.realpath(cfg["root_dir"])
    if not os.path.isdir(root):
        print(f"错误:root_dir 不存在或不是文件夹:{root}")
        sys.exit(1)
    cfg["root_dir"] = root
    return cfg


CFG = None  # 启动时由 main() 填入


# ---------- 路径安全 ----------
def safe_resolve(rel_path):
    """把客户端传来的相对路径解析成 root_dir 内的绝对路径。
    任何试图跳出 root_dir 的路径(..、绝对路径、盘符等)返回 None。"""
    rel_path = (rel_path or "").strip().replace("\\", "/").lstrip("/")
    # 拒绝绝对路径与 Windows 盘符(如 C:)
    if os.path.isabs(rel_path) or (len(rel_path) >= 2 and rel_path[1] == ":"):
        return None
    full = os.path.realpath(os.path.join(CFG["root_dir"], rel_path))
    # realpath 之后必须仍在 root_dir 之内(防 .. 穿越与符号链接逃逸)
    if full != CFG["root_dir"] and not full.startswith(CFG["root_dir"] + os.sep):
        return None
    return full


def backup_file(full_path):
    """覆盖前把旧文件复制到 root_dir/.ai-bridge-backup/相对路径.时间戳"""
    rel = os.path.relpath(full_path, CFG["root_dir"])
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(CFG["root_dir"], BACKUP_DIR_NAME, rel + "." + stamp)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(full_path, "rb") as src, open(dest, "wb") as dst:
        dst.write(src.read())


# ---------- HTTP 处理 ----------
class Handler(BaseHTTPRequestHandler):
    server_version = "ai-local-bridge/1.0"

    # -- 小工具:发送 JSON 响应 --
    def send_json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # -- 鉴权:所有接口都必须带正确的 Bearer token --
    def check_auth(self):
        auth = self.headers.get("Authorization", "")
        expected = "Bearer " + CFG["token"]
        # compare_digest 防时序攻击
        if secrets.compare_digest(auth, expected):
            return True
        self.send_json(401, {"error": "unauthorized,请携带 Authorization: Bearer <token>"})
        return False

    # -- 解析 URL,返回 (路由, path参数) --
    def parse(self):
        # http.server 用 latin-1 解码请求行;这里还原成 UTF-8,
        # 以支持中文文件名(无论客户端是否做了百分号编码)
        try:
            raw = self.path.encode("iso-8859-1").decode("utf-8")
        except UnicodeError:
            raw = self.path
        parsed = urllib.parse.urlparse(raw)
        qs = urllib.parse.parse_qs(parsed.query)
        return parsed.path, qs.get("path", [""])[0]

    # ---------- GET:健康检查 / 列目录 / 下载文件 ----------
    def do_GET(self):
        route, rel = self.parse()
        if not self.check_auth():
            return

        if route == "/api/health":
            # 不返回 token 等敏感信息
            self.send_json(200, {"status": "ok", "root": CFG["root_dir"],
                                 "read_only": CFG["read_only"]})
            return

        if route == "/api/files":
            full = safe_resolve(rel)
            if full is None:
                self.send_json(400, {"error": "非法路径(禁止 .. 或绝对路径)"})
                return
            if os.path.isdir(full):
                # 列目录:返回 JSON 数组
                items = []
                for name in sorted(os.listdir(full)):
                    p = os.path.join(full, name)
                    items.append({
                        "name": name,
                        "type": "dir" if os.path.isdir(p) else "file",
                        "size": os.path.getsize(p) if os.path.isfile(p) else None,
                        "mtime": int(os.path.getmtime(p)),
                    })
                self.send_json(200, {"path": rel, "items": items})
            elif os.path.isfile(full):
                # 下载文件:文本类用 utf-8 文本返回,其余按二进制
                ext = os.path.splitext(full)[1].lower()
                if ext in TEXT_EXTS:
                    ctype = (mimetypes.guess_type(full)[0] or "text/plain") + "; charset=utf-8"
                else:
                    ctype = mimetypes.guess_type(full)[0] or "application/octet-stream"
                with open(full, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_json(404, {"error": "文件或目录不存在: " + rel})
            return

        self.send_json(404, {"error": "未知接口"})

    # ---------- PUT:写入 / 创建文件 ----------
    def do_PUT(self):
        route, rel = self.parse()
        if not self.check_auth():
            return
        if route != "/api/files":
            self.send_json(404, {"error": "未知接口"})
            return
        if CFG["read_only"]:
            self.send_json(403, {"error": "服务运行在只读模式,拒绝写入"})
            return

        full = safe_resolve(rel)
        if full is None or not rel:
            self.send_json(400, {"error": "非法路径(禁止 .. 或绝对路径)"})
            return
        # 禁止直接写备份目录,防止备份被篡改
        if rel.replace("\\", "/").startswith(BACKUP_DIR_NAME):
            self.send_json(403, {"error": "备份目录为只读"})
            return

        length = int(self.headers.get("Content-Length", 0))
        if length > MAX_BODY:
            self.send_json(413, {"error": "内容过大(上限 20MB)"})
            return
        raw = self.rfile.read(length)

        # 请求体两种格式:JSON {"content":"..."} 或 原始字节
        ctype = self.headers.get("Content-Type", "")
        if "application/json" in ctype:
            try:
                data = json.loads(raw.decode("utf-8"))["content"].encode("utf-8")
            except (ValueError, KeyError):
                self.send_json(400, {"error": 'JSON 格式应为 {"content": "..."}'})
                return
        else:
            data = raw

        backed_up = False
        if os.path.isfile(full):          # 覆盖旧文件前先自动备份
            backup_file(full)
            backed_up = True
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as f:
            f.write(data)
        self.send_json(200, {"ok": True, "path": rel, "bytes": len(data),
                             "backed_up": backed_up})

    # ---------- POST:创建目录 ----------
    def do_POST(self):
        route, rel = self.parse()
        if not self.check_auth():
            return
        if route != "/api/files/mkdir":
            self.send_json(404, {"error": "未知接口"})
            return
        if CFG["read_only"]:
            self.send_json(403, {"error": "服务运行在只读模式,拒绝创建目录"})
            return
        full = safe_resolve(rel)
        if full is None or not rel:
            self.send_json(400, {"error": "非法路径(禁止 .. 或绝对路径)"})
            return
        os.makedirs(full, exist_ok=True)
        self.send_json(200, {"ok": True, "path": rel})

    # 精简日志:只打印一行,不记录 token
    def log_message(self, fmt, *args):
        print("[%s] %s" % (time.strftime("%H:%M:%S"), fmt % args))


# ---------- 入口 ----------
def main():
    global CFG
    CFG = load_config()
    print("=" * 60)
    print("ai-local-bridge 已启动(按 Ctrl+C 停止)")
    print(f"  受控文件夹 : {CFG['root_dir']}")
    print(f"  监听地址   : http://{CFG['host']}:{CFG['port']}")
    print(f"  只读模式   : {'是' if CFG['read_only'] else '否'}")
    print(f"  访问令牌   : {CFG['token']}")
    print("  下一步:运行 start_tunnel.bat 获取公网地址,把【公网地址+令牌】发给 AI。")
    print("=" * 60)
    ThreadingHTTPServer((CFG["host"], CFG["port"]), Handler).serve_forever()


if __name__ == "__main__":
    main()
