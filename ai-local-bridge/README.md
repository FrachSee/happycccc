# ai-local-bridge —— 自己掌控的「本机 ↔ 云端 AI」文件桥

一个**全部代码可自己审计**的极小工具(单文件 Python,约 300 行,零第三方依赖),
替代闭源的"本机↔云端安全通道"类软件。它在你的电脑上开一个只能访问
**你指定的一个文件夹**的 HTTP 接口,再由你自己运行 cloudflared 隧道把它临时
暴露给云端 AI 使用。

- 无遥测、不上传任何数据到作者服务器(根本没有作者服务器)
- 只监听本机 127.0.0.1,外网入口完全由你自己开关
- 所有请求必须携带随机生成的访问令牌(token)
- 覆盖文件前自动备份,支持只读模式

提供两种用法:**图形界面(推荐,可打包成 EXE 双击使用)** 和 **命令行脚本**。

---

## 〇、下载 cloudflared(两种用法都需要,只做一次)

到 <https://github.com/cloudflare/cloudflared/releases/latest> 下载
`cloudflared-windows-amd64.exe`,**改名为 `cloudflared.exe`**。
- 用图形界面/EXE:放到 **AIBridge.exe 同目录**(源码运行则放本文件夹);
- 用命令行脚本:放到本文件夹。

cloudflared 是 Cloudflare 官方开源的隧道工具,只负责把公网请求转发到你本机。

## 一、方式 A:图形界面(推荐)

### A1. 直接打包成 EXE(一次打包,之后双击即用)

在 Windows 上:

1. 安装 Python 3(<https://www.python.org/downloads/>,勾选 "Add Python to PATH");
2. 双击 `build_exe.bat`,等待 1-2 分钟,产物在 `dist\AIBridge\` 文件夹;
3. 把 `cloudflared.exe` 复制进 `dist\AIBridge\`(脚本会自动帮你复制,若本文件夹已有);
4. 以后双击 `dist\AIBridge\AIBridge.exe` 即可,整个文件夹也可拷给其他电脑用(对方无需装 Python)。

> 说明:PyInstaller 无法在 Linux/Mac 上打包 Windows EXE,所以打包这一步必须在 Windows 上做,双击 `build_exe.bat` 全自动完成。

### A2. 不打包,直接用源码运行图形界面

装好 Python 后双击运行 `gui_app.py`(或命令行 `python gui_app.py`)。

### A3. 图形界面怎么用(三步)

1. 点「浏览…」选择允许 AI 访问的文件夹(例如 `D:/剧本`);
2. 点绿色「**启动桥接**」—— 会同时启动本机服务和 cloudflared 隧道,
   等「公网地址」一栏显示 `https://xxx.trycloudflare.com` 即就绪;
3. 底部会自动生成一段**发给云端 AI 的话术**(含网址、令牌、API 用法),
   点「**复制话术**」,粘贴发给 AI 即可。

用完点「停止桥接」或直接关窗口,外网立刻无法访问你的电脑。
令牌保存在同目录 `config.json` 里,重启不变;想换令牌就把里面的 `token` 清空。

## 二、方式 B:命令行脚本(首次配置)

先安装 Python 3(同 A1 第 1 步),然后:

1. 双击 `start.bat`,它会自动生成 `config.json`;
2. 用记事本打开 `config.json`,把 `root_dir` 改成你允许 AI 读写的文件夹,例如:

```json
{
  "root_dir": "D:/剧本",
  "port": 8787,
  "host": "127.0.0.1",
  "token": "",
  "read_only": false
}
```

   - `token` 留空即可,启动时会自动生成一串随机令牌并写回;
   - 只想让 AI 读、不许改文件,把 `read_only` 改成 `true`。
3. 保存文件。

## 三、方式 B:日常使用(每次三步)

1. **双击 `start.bat`** —— 启动本机服务,窗口里会显示你的访问令牌(token);
2. **双击 `start_tunnel.bat`** —— 建立隧道,等它打印出一行形如
   `https://随机单词.trycloudflare.com` 的网址;
3. **把下面这段话发给云端 AI**(替换成你自己的网址和令牌):

   > 我的文件桥地址是 https://xxxx.trycloudflare.com ,
   > 访问令牌是 `你的token` 。
   > 接口:GET/PUT `/api/files?path=相对路径`(读/写文件、列目录),
   > POST `/api/files/mkdir?path=相对路径`(建目录),
   > 所有请求需要请求头 `Authorization: Bearer 令牌`。

用完后**关闭两个黑窗口**即彻底断开,外网无法再访问你的电脑。

## 四、接口一览(给 AI / 开发者看)

所有接口都要求请求头 `Authorization: Bearer <token>`。

| 接口 | 说明 |
| --- | --- |
| `GET /api/health` | 服务状态、受控文件夹路径、是否只读 |
| `GET /api/files?path=a/b` | `path` 是目录 → 返回 JSON 文件列表;是文件 → 返回文件内容(md/txt 等按 UTF-8 文本) |
| `PUT /api/files?path=a/b.md` | 写入/新建文件。请求体为原始内容,或 JSON `{"content":"..."}`;覆盖旧文件前自动备份 |
| `POST /api/files/mkdir?path=a/b` | 创建目录(含多级) |

`path` 只能是**相对路径**,`..`、绝对路径、盘符一律返回 400。
备份存放在 `受控文件夹/.ai-bridge-backup/`,按时间戳命名,可随时手动恢复。

## 五、常见问题

- **网址每次都变?** 是的,quick tunnel 免费且免注册,代价是每次重启网址随机变化,重新发给 AI 即可。
- **隧道连不上 / 很慢?** cloudflared 在中国大陆网络下稳定性一般,断了就重开 `start_tunnel.bat`;也可以自备其他转发方式,只要最终转发到 `127.0.0.1:8787` 即可。
- **想换令牌?** 关闭服务,把 `config.json` 里的 `token` 清空成 `""`,重新启动会生成新令牌(旧令牌立即失效)。
- **GUI 提示"未找到 cloudflared.exe"?** 把 `cloudflared.exe` 放到 AIBridge.exe(或 `gui_app.py`)同目录,停止后重新点「启动桥接」。
- **杀毒软件报警 EXE?** PyInstaller 打包的程序偶尔会被误报;全部源码就在本文件夹,可自行审计后自己打包,不放心就用方式 B 的纯脚本运行。
- **安全须知**:使用前请阅读 [SECURITY.md](SECURITY.md)。安全设计对两种用法完全一致(同一个 `server.py`)。
