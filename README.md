# DeepSeek Harness · Windows 自包含启动方案

把 [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) 在 Windows 上装成
**自包含、可移植、双击即用**的本地应用，并绕开这条路上几个真实存在的坑。

实测环境：Windows 11 · Node.js v24 · PowerShell 5.1 · Chrome / Edge。

**中文** | [English](#english)

**目录**：[解决什么](#这个方案解决什么) · [前置要求](#前置要求) · [快速开始](#快速开始) · [文件说明](#文件说明) · [目录结构](#运行后的目录结构) · [工作原理](#工作原理) · [编码铁律](#三条编码铁律) · [故障排查](#故障排查) · [不包含什么](#这个仓库不包含什么) · [已知限制](#已知限制) · [参考](#参考)

**Contents**: [What this solves](#what-this-solves) · [Requirements](#requirements) · [Quick start](#quick-start) · [Files](#files) · [Layout](#layout-after-setup) · [How it works](#how-it-works) · [Three rules](#three-rules-this-project-learned-the-hard-way) · [Troubleshooting](#troubleshooting) · [Not included](#what-this-repository-does-not-contain) · [Known limitations](#known-limitations) · [References](#references)

---

## 这个方案解决什么

| 你会遇到的问题 | 本方案的做法 |
|---|---|
| dsh 的 PowerShell 执行器**静默回落到 Windows PowerShell 5.1**（`pwsh` 不在 PATH、PS7 不在它探测的标准位置），导致 `-replace` 脚本块、`-SkipExecutionPolicy` 等一大批命令失败 | 安装**免安装便携版 PowerShell 7**，并用 dsh 的 `pwshPath` 配置项钉住它。不需要管理员权限 |
| harness 界面**混在你日常浏览器的标签页里**，和平时上网互相干扰 | 用独立的浏览器配置目录 + `--app=` 无边框窗口打开，和日常浏览器完全隔离 |
| harness 启动时**弹出一个终端窗口**，不像一个应用 | `dsh-launch.exe` 是 GUI 子系统程序，**天生没有控制台**，并用 `CreateNoWindow` 拉起守护进程；关掉浏览器窗口即停服 |
| 换设备或改目录后 **DSH_HOME 不确定**，配置、凭据、会话散落各处 | 启动器自动把 `DSH_HOME` 钉到**脚本所在目录**下的 `dsh-home`，整个方案跟着文件夹走 |
| 脚本里一个中文标点就让 **PowerShell 直接启动失败**，报 `TerminatorExpectedAtEndOfString` | 所有 `.ps1` 保持**纯 ASCII**，从根上免疫编码问题 |

---

## 前置要求

- **Windows 10 / 11**
- **Node.js（LTS 版）** —— 必需，启动器通过 `npx` 拉取并运行 dsh。装完确认 `node --version` 和 `npx --version` 都能用
- **Chrome 或 Edge** —— 用于打开界面窗口（Edge 是系统自带的，一定有）
- **首次运行需要联网** —— 下载 PowerShell 7（约 100 MB）和 dsh 本体
- PowerShell 5.1（系统自带，无需额外安装）

> 不需要管理员权限。所有东西都装在用户目录下。

---

## 快速开始

1. **把这个文件夹整个复制到你想要的位置**，例如 `D:\dsh`。
   路径建议**纯 ASCII**（避免中文、空格、特殊符号），省掉一类无谓的麻烦。

2. **运行一次安装脚本**。在该文件夹里打开 PowerShell，执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   它会依次完成：建立目录结构 → 检查 Node → 装便携版 PowerShell 7 →
   写 dsh 配置补丁 → 创建桌面快捷方式。**可重复运行，不会重复下载。**

3. **双击桌面的「DeepSeek Harness」**。
   首次启动会下载 dsh 本体，需要几分钟。之后每次启动都是秒开。

4. *（可选）* 首次成功启动后，再执行一次：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\make-icon.ps1
   ```

   从你本机已安装的 dsh 前端资源生成 DeepSeek 图标，并应用到桌面快捷方式。

---

## 文件说明

| 文件 | 作用 | 编码要求 |
|---|---|---|
| `dsh-launch.exe` | **桌面上双击的就是它**。编译出的 GUI 子系统程序，**天生没有控制台**，只负责用 `CreateNoWindow` 拉起守护脚本 | 二进制，由 `setup.ps1` 编译 |
| `launcher.cs` | 上面那个 exe 的源码（约 15 行有效逻辑）。改完重跑 `setup.ps1` 即可重新编译 | 必须纯 ASCII |
| `start-dsh.ps1` | **守护进程**（见「工作原理」）。不显示窗口，写日志，关窗即停服 | 必须纯 ASCII |
| `setup.ps1` | **一次性安装**。建目录、装 PS7、写配置补丁、编译启动器、建快捷方式。幂等 | 必须纯 ASCII |
| `make-icon.ps1` | **可选**。从本机 dsh 的前端资源生成 `dsh.ico` 并应用到快捷方式 | 必须纯 ASCII |
| `stop-dsh.ps1` | **兜底停止**。只在"关窗没把服务停掉"这类异常情况下才用得上 | 必须纯 ASCII |
| `stop-dsh.cmd` | 上面那个脚本的双击包装（省得右键"用 PowerShell 运行"） | 纯 ASCII |
| `README.md` | 本文档 | UTF-8 |

---

## 运行后的目录结构

```
<你放的位置>\
├── dsh-launch.exe         # ★ 桌面快捷方式指向它（无控制台的启动器）
├── launcher.cs            # 上面那个 exe 的源码
├── start-dsh.ps1          # 守护进程
├── setup.ps1
├── make-icon.ps1
├── stop-dsh.ps1           # 兜底停止
├── stop-dsh.cmd           # 双击即可执行上面的脚本
├── README.md
├── dsh.ico                # make-icon.ps1 生成（可选）
│
├── logs\                  # ★ 原来看控制台的那些内容
│   ├── dsh.log                  # 本次运行的服务器输出
│   ├── dsh.1.log                # 上一次运行
│   ├── dsh.2.log                # 上上次运行
│   └── launcher.log             # 守护进程自己的判断记录（排查"关窗没停"用）
│
├── run\                   # 运行时状态
│   └── server.pid               # 服务器进程号，给 stop-dsh.ps1 用
│
├── dsh-home\              # ★ 全部运行时状态都在这里
│   ├── settings.yaml            # dsh 设置
│   ├── .credentials.yaml        # ★ API 密钥（明文，注意保护）
│   ├── cordis.patch.yml         # 本方案写入的 pwshPath 补丁
│   ├── sessions\                # 会话记录
│   ├── storages\                # 工作区登记
│   ├── npm-cache\               # npx 缓存（dsh 本体在这里）
│   └── browser-profile\         # 独立的浏览器配置（首次启动时生成）
│
└── dsh-workspace\         # dsh 进程的工作目录
```

**整个文件夹就是这套方案的全部。** 复制到另一台机器、换个盘符都能直接跑。

想彻底重置：删掉 `dsh-home` 即可（**注意里面有你保存的 API 密钥**）。
只想清掉浏览器状态：删 `dsh-home\browser-profile`，不影响你日常浏览器。

---

## 工作原理

### 1. 它是「本地服务器 + 浏览器客户端」，不是网页

```
桌面快捷方式 → dsh-launch.exe        ← GUI 子系统，天生没有控制台，启动后立即退出
  └─ powershell.exe (CreateNoWindow) ← 也不创建控制台窗口
       └─ start-dsh.ps1             ← 守护进程，全程不显示窗口，跟随整个会话
            ├─ 轮转日志；停掉上一轮可能残留的服务
            ├─ 启动：npx @deepseek-ai/dsh web --no-open
            │    └─ 输出重定向到 logs\dsh.log
            ├─ 轮询该日志文件，抓到 dsh web: <认证 URL>
            ├─ 用独立窗口打开该 URL                  ← 浏览器只是"显示器"
            ├─ 循环检查：还有没有 Chrome 进程占着我们的 browser-profile
            └─ 窗口一关 → 结束服务器进程树 → 自己退出
```

**为什么需要 `dsh-launch.exe` 这一层**：守护进程是 PowerShell 脚本，本来就需要控制台。
Windows 11 把 Windows Terminal 设为默认终端后，启动控制台程序会由 WT 接管并**开出一个窗口**，
`-WindowStyle Hidden` 挡不住它——那个参数用 `SW_HIDE`，只能隐藏"已经存在的控制台窗口"，
而实际出现的窗口属于 Windows Terminal。`dsh-launch.exe` 是 **GUI 子系统**程序（编译时
`/target:winexe`），**根本不创建控制台**；它再用 `CreateNoWindow = true` 启动 PowerShell，
即"请不要创建控制台窗口"，于是 Windows Terminal 无从介入。

- **真正在读写你文件、跑命令、调 API 的，是本地的那个 Node 进程。**
- **关掉浏览器窗口 = 关掉 harness。** 守护进程发现窗口消失后会结束服务器并退出——这就是本方案追求的"像 .exe"的体验。
- 服务器默认只绑定回环地址（`127.0.0.1`），不接受局域网访问；认证 URL 带一次性 token 用于建立会话。

#### 日志

原来在控制台里滚动的内容，现在全部落盘：

| 文件 | 内容 |
|---|---|
| `logs\dsh.log` | **服务器的全部输出**（就是原来控制台里看到的东西），每次启动重新开始 |
| `logs\dsh.1.log` / `dsh.2.log` | 上一次 / 上上次运行的输出，**保留最近 3 轮** |
| `logs\launcher.log` | 守护进程自己的判断：抓到的 URL、检测到的浏览器进程数、何时决定停服 |

出问题时**先看 `dsh.log` 末尾**，再看 `launcher.log` 判断是服务本身的问题还是"关窗检测"的问题。

#### 为什么需要守护进程

原版是脚本用**管道**接住服务器输出，所以脚本必须一直活着、控制台也就一直在。
现在改成**输出重定向到文件**，脚本就能在后台轮询文件拿 URL——这是"窗口能关掉"的前提。

### 2. 为什么用 `--no-open` 加自己捕获 URL

dsh 默认会往你的**默认浏览器**里打开一个标签页——那样就和日常上网混在一起了。
`--no-open` 只关掉这个自动动作，**那行认证 URL 仍会正常打印**，启动器读它，再用独立窗口打开。

### 3. 浏览器隔离是怎么做的

```powershell
chrome.exe --app="<认证 URL>" `
           --user-data-dir="<dsh-home>\browser-profile" `
           --no-first-run --no-default-browser-check
```

- `--app=` 打开一个**没有标签栏、没有地址栏**的窗口
- `--user-data-dir=` 让它使用**独立的浏览器配置目录**：cookie、存储、历史、任务栏分组都与日常浏览器无关
- 依据：[Chromium 官方文档](https://chromium.googlesource.com/chromium/src/+/main/docs/windows_shortcut_and_taskbar_handling.md) —— `--app` 窗口有独立 AUMID，且 AUMID 包含 profile 名，"each profile's windows will be grouped together on the taskbar"

**对日常浏览器的影响**：仅磁盘上多一个配置文件夹、运行时多一个浏览器进程。不改默认浏览器、不改注册表、不碰你现有配置。

### 4. 为什么需要那个 dsh 配置补丁

dsh 的 PowerShell 执行器按固定顺序找 `pwsh`：

1. 配置项 **`pwshPath`** ← 本方案写入的就是这一条
2. `%ProgramFiles%\PowerShell\7\pwsh.exe`（非管理员不可写，所以没用这条）
3. `PATH` 里的每一项
4. **`Windows PowerShell 5.1`** ← 前三条都没有时的兜底，也是各种奇怪失败的来源

补丁写在 **home 层级**（`dsh-home\cordis.patch.yml`），dsh 会把它应用到**每一个 profile**，
而且是**热加载**的——写完立即生效，**不需要重启 dsh**。

---

## 三条编码铁律

下面三条都是本项目真实踩过的坑，而且都**极难排查**，务必遵守：

### 铁律一：`.ps1` 文件保持纯 ASCII

**Windows PowerShell 5.1 读取没有 BOM 的 `.ps1` 时，用的是系统 ANSI 代码页，不是 UTF-8。**

后果不是"乱码难看"这么轻——是**硬解析失败，脚本一行都不执行**：

```
At ...\start-dsh.ps1:54 char:85
+ ... e-Host "<乱码>" Chrome / Edge ... $url"
The string is missing the terminator: ".
...
    + FullyQualifiedErrorId : TerminatorExpectedAtEndOfString
```

字符串字面量里的非 ASCII 字符会让**结束引号对不上**，解析器直接放弃。
后面那些 `Missing closing '}'` 全是**级联错误**，真凶只有第一条。

排查 PowerShell 解析错误时**永远看第一条**。

| 文件由谁读取 | 含非 ASCII 时的 BOM |
|---|---|
| `powershell.exe`（PS 5.1）执行 `.ps1` | **必须带 UTF-8 BOM**（或保持纯 ASCII） |
| `pwsh`（PS 7）执行 `.ps1` | 可不带（PS 7 默认按 UTF-8 读） |
| Node 读的 `.yaml` / `.json` / `.js` | **不要** BOM |

本项目的选择是**纯 ASCII**：无论有没有 BOM 都不会坏，也不用指望后来的编辑者记得加 BOM。

### 铁律二：不要用数组拼接构造多行文件

```powershell
# 危险：这个表达式可能被拆成独立数组元素
$lines = @( 'a', "x" + $var + "y" )
```

一旦被拆散，值就会变成跨行的内容。构造配置文件时用**单引号 here-string**（字面内容、不插值）
或直接写文件，写完立即重新读取校验。

### 铁律三：`Start-Process -ArgumentList` 传数组**不会加引号**

这是本项目踩过的第三个坑，也是最隐蔽的一个——它**不报错**，只是静默失效。

```powershell
# 危险：数组元素只是用空格拼接，含空格的元素会被切成两个参数
Start-Process -FilePath $exe -ArgumentList @(
    "--app=$url",
    "--user-data-dir=$profilePath",   # 路径含空格 -> 被切断
    '--no-first-run'
)
```

实测证据（用 node 打印它收到的 argv）：

| 写法 | 接收方看到的 |
|---|---|
| 数组形式 | `["C:\Users\Chenhao","S\somewhere"]` ← **被切成两个** |
| 带引号的字符串形式 | `["C:\Users\Chenhao S\somewhere"]` ← 完整 |

后果：`--user-data-dir` 指向了一个不存在的目录，Chrome 静默退回**默认配置**，
"浏览器隔离"看起来配置正确却从未生效。**只要用户名或安装路径带空格就会中招。**

**正确写法**是把参数拼成**一个带引号的字符串**：

```powershell
$argumentLine = '--app="' + $url + '"' +
    ' --user-data-dir="' + $profilePath + '"' +
    ' --no-first-run'
Start-Process -FilePath $exe -ArgumentList $argumentLine
```

**注意区分**：`&` 调用运算符（`& $exe $arg1 $arg2`）**会**正确加引号，不受此影响。
只有 `Start-Process -ArgumentList` 的数组形式有这个陷阱。

---

## 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 双击后**毫无反应**（浏览器窗口也没出现） | 守护进程不显示窗口，出错时你看不到任何东西 | `dsh-launch.exe` 遇到致命错误会**弹一个消息框**并写 `logs\launcher.log`；先看这两处。要现场调试就手动跑 `powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1` |
| 双击后闪出一个窗口（标题带 `+` 标签按钮） | 快捷方式没指向 `dsh-launch.exe`，退化成了 PowerShell 直启，而你的默认终端是 Windows Terminal | 重跑 `setup.ps1` 重建快捷方式；确认 `dsh-launch.exe` 存在且能被编译出来 |
| 编译 `dsh-launch.exe` 失败 | 找不到 `csc.exe`（极罕见，Windows 自带） | `setup.ps1` 会自动退回 PowerShell 直启（会有窗口）；或手动用 `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` 编译 |
| 关掉浏览器窗口后**服务还在跑** | "窗口是否关闭"的判断失准，或者守护进程被任务管理器杀了 | 看 `logs\launcher.log` 最后几行；然后运行 `stop-dsh.cmd` |
| 浏览器窗口没开，服务却起来了 | 没找到 Chrome / Edge | `launcher.log` 里有记录；手动打开 `dsh.log` 里那行 `dsh web:` URL，用 `stop-dsh.cmd` 停止 |
| `TerminatorExpectedAtEndOfString` | `.ps1` 里有非 ASCII 且无 BOM | 把文件改回纯 ASCII，或另存为"UTF-8 带 BOM" |
| `npx : 无法将...识别为 cmdlet` | 没装 Node.js | 装 [Node.js LTS](https://nodejs.org)，重开终端 |
| 启动很慢、卡在下载 | 首次运行要拉 dsh 本体 | 正常，几分钟；`dsh.log` 里能看到下载过程 |
| 端口 3080 被占用 | 有别的 dsh 实例在跑 | `launcher.log` 会警告；关掉旧的，或用 `stop-dsh.cmd` |
| Agent 跑命令时各种奇怪报错 | 回落到 PowerShell 5.1 了 | 确认 `dsh-home\cordis.patch.yml` 存在、里面的 `pwshPath` 指向的文件真的存在，然后重跑 `setup.ps1` |
| 换了设备后 Agent 又出问题 | 补丁里的 `pwshPath` 是**绝对路径**，且 dsh **不校验它是否存在** | 在新设备上重跑 `setup.ps1` |
| 想换图标但提示找不到 favicon.svg | dsh 前端资源只在首次启动后才下载 | 先成功启动一次，再跑 `make-icon.ps1` |
| 改了图标但任务栏没变 | Windows 有图标缓存 | 注销 / 重启，或重启 explorer.exe |

---

## 这个仓库不包含什么

- **没有 `dsh-home/`** —— 里面有你的 **API 密钥、会话记录、全部个人状态**。务必加入 `.gitignore`（本仓库已含），**永远不要提交**。
- **没有 `.ico` 文件** —— 图标由 `make-icon.ps1` 从**你本机**已安装的 dsh 前端资源生成，仓库不重新分发 DeepSeek 的图形资源。该脚本只是转换你机器上已有的一份副本。

---

## 已知限制

- **「关窗即停服」已端到端验证通过**，但它是一个**推断**而非浏览器主动通知：守护进程靠"还有没有 Chrome 进程的命令行里带我们的 `browser-profile` 路径"来判断窗口是否还在（实测在同时跑着日常 Chrome 的机器上，两组进程能干净区分）。实测关窗到完全停止约 **5–6 秒**，且上一轮的 `cmd`/`node` 进程全部消失、无孤儿残留。两个理论边界仍存在：Chrome 若在窗口关闭后保留后台进程，服务可能不停；启动瞬间的进程抖动靠"连续 2 次检测不到"吸收。**`logs\launcher.log` 会记录每一次判断**，真出问题时能定位。
- **关掉窗口会立即结束正在跑的任务。** 这是你要的语义，但代价要清楚：误关窗口 = 任务中断。
- **如果守护进程被强杀**（任务管理器结束进程），服务器会成为看不见的孤儿，之后关窗也不会停它。用 `stop-dsh.cmd` 收拾。（实测：杀掉守护进程后服务器仍在写文件、继续运行。）
- **换了默认终端就不再需要 `dsh-launch.exe`**：如果你以后把「默认终端应用程序」改成"Windows 控制台主机"，`-WindowStyle Hidden` 会重新生效，那一层可以去掉。反过来说，`dsh-launch.exe` 存在的原因就是 Windows Terminal。
- **任务栏图标（已实测通过）**：窗口**运行时**的任务栏图标**确实**是 DeepSeek 图标，并且与日常 Chrome **分成两个独立的任务栏项**（2026-09-21 截图确认）。Chromium 文档提到任务栏图标会 "badged with their profile icon"，但在本方案这种「独立 profile + `--app=`」组合下并未出现——所以不需要再走"安装为 PWA"那条路。
- **`pwshPath` 是绝对路径，且 dsh 不做存在性校验**。如果那个 PowerShell 7 目录被删除或移动，表现不是"回退到 5.1"，而是 **shell 直接不可用**。换设备或清理磁盘后请重跑 `setup.ps1`。
- 本方案只覆盖 **Windows**。其他平台不需要这些绕行（bash 执行器没有对应的回落问题）。

---

## 参考

- [Chromium · Windows Shortcut and Pinned Taskbar Icon handling](https://chromium.googlesource.com/chromium/src/+/main/docs/windows_shortcut_and_taskbar_handling.md)
- [PowerShell 7 releases](https://github.com/PowerShell/PowerShell/releases)

---
---

<a id="english"></a>

# DeepSeek Harness · Windows self-contained launcher

[中文](#deepseek-harness--windows-自包含启动方案) | **English**

Install [DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh) on Windows as a
**self-contained, portable, double-click-and-go** local application - and sidestep a handful of
real traps on the way.

Verified on: Windows 11 · Node.js v24 · PowerShell 5.1 · Chrome / Edge.

---

## What this solves

| Problem you would hit | What this does |
|---|---|
| dsh's PowerShell executor **silently falls back to Windows PowerShell 5.1** (`pwsh` is not on PATH and PS7 is not in the location dsh probes), breaking `-replace` script blocks, `-SkipExecutionPolicy` and a whole class of commands | Installs a **portable PowerShell 7** and pins it through dsh's `pwshPath` setting. No administrator rights needed |
| The harness UI is **buried among your everyday browser tabs** | Opens it in a `--app=` chromeless window backed by a **dedicated browser profile**, fully isolated from your normal browsing |
| A **console window pops up** at launch, so it does not feel like an application | `dsh-launch.exe` is a GUI-subsystem program with **no console at all**, and starts the supervisor with `CreateNoWindow`; closing the browser window stops the service |
| **DSH_HOME is ambiguous** after moving machines or folders, scattering config, credentials and sessions | The launcher pins `DSH_HOME` to `dsh-home` **next to the script**, so the whole setup travels with the folder |
| A single non-ASCII character makes **PowerShell refuse to start**, failing with `TerminatorExpectedAtEndOfString` | Every `.ps1` stays **pure ASCII**, which is immune to encoding problems by construction |

---

## Requirements

- **Windows 10 / 11**
- **Node.js (LTS)** - required: the launcher pulls and runs dsh through `npx`. Confirm both `node --version` and `npx --version` work.
- **Chrome or Edge** - used for the UI window (Edge ships with Windows, so this is always satisfied)
- **Internet access on first run** - to download PowerShell 7 (~100 MB) and dsh itself
- PowerShell 5.1 (built into Windows; nothing to install)

> No administrator rights. Everything installs under your user profile.

---

## Quick start

1. **Copy this whole folder wherever you want it**, for example `D:\dsh`.
   An **ASCII-only path** (no non-ASCII characters, spaces or symbols) avoids a whole category of
   needless trouble.

2. **Run the setup script once.** Open PowerShell in that folder and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   It builds the layout, checks Node, installs portable PowerShell 7, writes the dsh config patch,
   compiles the launcher and creates the desktop shortcut.
   **Safe to re-run; it will not download twice.**

3. **Double-click "DeepSeek Harness" on your desktop.**
   The first launch downloads dsh itself and takes a few minutes; later launches are quick.
   Nothing appears on screen until the browser window opens by itself.

4. *(Optional)* After the first successful launch, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\make-icon.ps1
   ```

   It builds a DeepSeek icon from the dsh frontend asset already on your machine and applies it to
   the desktop shortcut.

---

## Files

| File | Purpose | Encoding |
|---|---|---|
| `dsh-launch.exe` | **What the desktop shortcut runs.** A compiled GUI-subsystem program with **no console at all**; its only job is to start the supervisor with `CreateNoWindow` | Binary, compiled by `setup.ps1` |
| `launcher.cs` | Source of that exe (about 15 lines of real logic). Edit it and re-run `setup.ps1` to rebuild | Must stay pure ASCII |
| `start-dsh.ps1` | **The supervisor** (see "How it works"). No window, writes the logs, stops the service when the browser window closes | Must stay pure ASCII |
| `setup.ps1` | **One-time setup.** Layout, PS7, config patch, launcher build, shortcut. Idempotent | Must stay pure ASCII |
| `make-icon.ps1` | **Optional.** Builds `dsh.ico` from your local dsh frontend asset and applies it to the shortcut | Must stay pure ASCII |
| `stop-dsh.ps1` | **Fallback stop.** Only needed when closing the window failed to stop the service | Must stay pure ASCII |
| `stop-dsh.cmd` | Double-click wrapper around the script above | Pure ASCII |
| `README.md` | This document | UTF-8 |

---

## Layout after setup

```
<wherever you put it>\
├── dsh-launch.exe         # the desktop shortcut points here (console-free launcher)
├── launcher.cs            # source of the exe above
├── start-dsh.ps1          # the supervisor
├── setup.ps1
├── make-icon.ps1
├── stop-dsh.ps1           # fallback stop
├── stop-dsh.cmd           # double-click to run the script above
├── README.md
├── dsh.ico                # built by make-icon.ps1 (optional)
│
├── logs\                  # what used to scroll in the console
│   ├── dsh.log                  # server output, current run
│   ├── dsh.1.log                # previous run
│   ├── dsh.2.log                # the run before that
│   └── launcher.log             # the supervisor's own decisions
│
├── run\                   # runtime state
│   └── server.pid               # server process id, used by stop-dsh.ps1
│
├── dsh-home\              # every bit of runtime state lives here
│   ├── settings.yaml            # dsh settings
│   ├── .credentials.yaml        # API key in plain text - protect it
│   ├── cordis.patch.yml         # the pwshPath patch this project writes
│   ├── sessions\                # session transcripts
│   ├── storages\                # workspace registry
│   ├── npm-cache\               # npx cache (dsh itself lives here)
│   └── browser-profile\         # isolated browser profile (created on first launch)
│
└── dsh-workspace\         # working directory of the dsh process
```

**That folder is the entire setup.** Copy it to another machine or another drive and it runs.

Full reset: delete `dsh-home` (**it holds your API key**).
Reset only the browser state: delete `dsh-home\browser-profile`; your normal browser is untouched.

---

## How it works

### 1. It is a local server plus a browser client, not a website

```
desktop shortcut -> dsh-launch.exe     <- GUI subsystem, no console, exits immediately
  └─ powershell.exe (CreateNoWindow)   <- also creates no console window
       └─ start-dsh.ps1                <- the supervisor, windowless for the whole session
            ├─ rotates logs; stops a leftover server from the previous run
            ├─ starts: npx @deepseek-ai/dsh web --no-open
            │    └─ output redirected into logs\dsh.log
            ├─ polls that log for "dsh web: <authenticated URL>"
            ├─ opens that URL on the dedicated profile   <- the browser is just a display
            ├─ polls: is any Chrome process still using our browser-profile?
            └─ window gone -> kill the server tree -> exit
```

**Why the `dsh-launch.exe` layer is needed.** The supervisor is a PowerShell script, so it needs a
console. Once Windows Terminal is the default terminal application, starting a console program
hands the console to WT, which **opens a window**; `-WindowStyle Hidden` cannot prevent that,
because the flag maps to `SW_HIDE` and only hides a console window that already exists - the window
you actually see belongs to Windows Terminal. `dsh-launch.exe` is a **GUI-subsystem** program
(`/target:winexe`) and creates **no console at all**; it then starts PowerShell with
`CreateNoWindow = true`, which asks Windows not to create a console window, so Windows Terminal is
never involved.

- **The process doing the real work - files, commands, API calls - is that local Node process.**
- **Closing the browser window shuts the harness down.** The supervisor notices and stops the server. That is the "feels like an .exe" behaviour this project is after.
- The server binds the loopback address only (`127.0.0.1`) and is not reachable from the LAN; the authenticated URL carries a one-time token used to establish the session.

#### Logs

Everything that used to scroll in the console now goes to disk:

| File | Contents |
|---|---|
| `logs\dsh.log` | **All server output** - exactly what the console used to show. Fresh on every launch |
| `logs\dsh.1.log` / `dsh.2.log` | The previous run and the one before that; **the last 3 runs are kept** |
| `logs\launcher.log` | The supervisor's own decisions: the URL it captured, how many browser processes it saw, when it decided to stop |

When something breaks, **read the end of `dsh.log` first**, then `launcher.log`, to tell a
server problem from a window-detection problem.

#### Why a supervisor at all

The original script used a **pipeline** to capture the server's output, which meant the script had
to stay alive and its console stayed on screen. Redirecting the output **to a file** instead lets
the script poll that file for the URL in the background - and that is what makes closing the window
possible.

### 2. Why `--no-open` plus capturing the URL ourselves

By default dsh opens a tab in your **default browser**, mixing the harness into your everyday
browsing. `--no-open` disables only that automatic step; the authenticated URL is **still printed**,
so the launcher reads it and opens it in the isolated window instead.

### 3. How the browser isolation works

```powershell
chrome.exe --app="<authenticated URL>" `
           --user-data-dir="<dsh-home>\browser-profile" `
           --no-first-run --no-default-browser-check
```

- `--app=` opens a window with **no tab strip and no address bar**
- `--user-data-dir=` gives it a **dedicated browser profile**: cookies, storage, history and taskbar grouping are all separate from your everyday browser
- Source: [Chromium documentation](https://chromium.googlesource.com/chromium/src/+/main/docs/windows_shortcut_and_taskbar_handling.md) - `--app` windows carry their own AUMID, and the AUMID includes the profile name, so "each profile's windows will be grouped together on the taskbar"

**Impact on your everyday browser:** one extra profile folder on disk, and one extra browser
process while the harness runs. No default-browser change, no registry change, nothing done to your
existing profile.

### 4. Why the dsh config patch is needed

dsh's PowerShell executor resolves `pwsh` in a fixed order:

1. the **`pwshPath`** config value <- what this project writes
2. `%ProgramFiles%\PowerShell\7\pwsh.exe` (not writable without administrator rights, so unused here)
3. every `PATH` entry
4. **`Windows PowerShell 5.1`** <- the fallback when nothing above matches, and the source of a whole class of odd failures

The patch lives at the **home level** (`dsh-home\cordis.patch.yml`), which dsh applies to **every
profile**, and it is **hot-reloaded** - it takes effect immediately, with **no dsh restart**.

---

## Three rules this project learned the hard way

### Rule 1: keep `.ps1` files pure ASCII

**When Windows PowerShell 5.1 reads a `.ps1` that has no BOM, it uses the system ANSI code page,
not UTF-8.**

The consequence is not "ugly mojibake". It is a **hard parse failure - not one line of the script runs**:

```
At ...\start-dsh.ps1:54 char:85
+ ... e-Host "<mojibake>" Chrome / Edge ... $url"
The string is missing the terminator: ".
...
    + FullyQualifiedErrorId : TerminatorExpectedAtEndOfString
```

A non-ASCII character inside a string literal leaves the **closing quote unmatched**, and the parser
gives up. The `Missing closing '}'` errors that follow are all **cascade**; only the first one is
real. **Always read the first error** when diagnosing a PowerShell parse failure.

| Who reads the file | BOM when it contains non-ASCII |
|---|---|
| `powershell.exe` (PS 5.1) running a `.ps1` | **UTF-8 BOM required** (or keep it pure ASCII) |
| `pwsh` (PS 7) running a `.ps1` | Optional (PS 7 reads UTF-8 by default) |
| `.yaml` / `.json` / `.js` read by Node | **No BOM** |

This project chooses **pure ASCII**: immune whether or not a BOM is present, and no need to trust a
future editor to remember the BOM.

### Rule 2: do not build multi-line files by array concatenation

```powershell
# Dangerous: this expression can be split into separate array elements
$lines = @( 'a', "x" + $var + "y" )
```

Once split, the value becomes content spanning several lines. When generating a config file, use a
**single-quoted here-string** (literal, no interpolation) or write the file directly - then read it
back immediately to verify.

### Rule 3: `Start-Process -ArgumentList` does **not** quote an array

The third trap, and the most insidious, because it **raises no error** - it just silently stops
working.

```powershell
# Dangerous: array elements are simply joined with spaces, so an element
# containing a space is split into two arguments
Start-Process -FilePath $exe -ArgumentList @(
    "--app=$url",
    "--user-data-dir=$profilePath",   # path contains a space -> split
    '--no-first-run'
)
```

Measured evidence (printing the argv a child actually received):

| Form | What the receiver saw |
|---|---|
| array | `["C:\Users\Chenhao","S\somewhere"]` <- **split in two** |
| one quoted string | `["C:\Users\Chenhao S\somewhere"]` <- intact |

The consequence: `--user-data-dir` pointed at a directory that does not exist, Chrome silently fell
back to the **default profile**, and the "browser isolation" looked correctly configured while never
actually working. **Any user name or install path containing a space triggers this.**

**The correct form** is to assemble the arguments as **one quoted string**:

```powershell
$argumentLine = '--app="' + $url + '"' +
    ' --user-data-dir="' + $profilePath + '"' +
    ' --no-first-run'
Start-Process -FilePath $exe -ArgumentList $argumentLine
```

**Note the distinction:** the `&` call operator (`& $exe $arg1 $arg2`) **does** quote correctly and
is unaffected. Only the array form of `Start-Process -ArgumentList` has this trap.

---

## Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| Double-click does **nothing at all** (no browser window either) | The supervisor runs windowless, so you cannot see an error | `dsh-launch.exe` shows a **message box** on fatal errors and writes `logs\launcher.log`; check both. To debug live, run `powershell -ExecutionPolicy Bypass -File .\start-dsh.ps1` |
| A window flashes on double-click (title bar has a `+` tab button) | The shortcut is not pointing at `dsh-launch.exe` and fell back to PowerShell, and your default terminal is Windows Terminal | Re-run `setup.ps1` to rebuild the shortcut; confirm `dsh-launch.exe` exists and compiles |
| Compiling `dsh-launch.exe` fails | `csc.exe` not found (very rare; it ships with Windows) | `setup.ps1` falls back to launching PowerShell directly (a window may appear); or compile by hand with `%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe` |
| The **service keeps running** after closing the browser window | Window-closed detection was wrong, or the supervisor was killed from Task Manager | Read the end of `logs\launcher.log`, then run `stop-dsh.cmd` |
| No browser window, but the service started | Chrome / Edge not found | `launcher.log` records it; open the `dsh web:` URL from `dsh.log` by hand, and stop with `stop-dsh.cmd` |
| `TerminatorExpectedAtEndOfString` | A `.ps1` has non-ASCII and no BOM | Make the file pure ASCII again, or save it as "UTF-8 with BOM" |
| `npx : The term ... is not recognized` | Node.js is not installed | Install [Node.js LTS](https://nodejs.org) and reopen the terminal |
| Very slow first start, appears to hang | The first run downloads dsh | Normal, a few minutes; `dsh.log` shows the download |
| Port 3080 already in use | Another dsh instance is running | `launcher.log` warns about it; stop the old one, or use `stop-dsh.cmd` |
| Odd failures when the agent runs commands | It fell back to PowerShell 5.1 | Check that `dsh-home\cordis.patch.yml` exists and that the file its `pwshPath` names really exists, then re-run `setup.ps1` |
| Agent problems reappear on a new machine | `pwshPath` is an **absolute path** and dsh **never checks that it exists** | Re-run `setup.ps1` on the new machine |
| No `favicon.svg` to build an icon from | The dsh frontend asset only exists after the first launch | Launch successfully once, then run `make-icon.ps1` |
| Icon changed but the taskbar still shows the old one | Windows caches icons | Sign out / reboot, or restart explorer.exe |

---

## What this repository does not contain

- **No `dsh-home/`** - it holds your **API key, session transcripts and all personal state**. It is listed in `.gitignore` (already included); **never commit it**.
- **No `.ico` file** - the icon is generated by `make-icon.ps1` from the dsh frontend asset **already on your machine**; the repository does not redistribute DeepSeek's artwork. The script only converts a copy you already have.

---

## Known limitations

- **"Closing the window stops the service" is verified end to end**, but it remains an **inference**, not a notification from the browser: the supervisor decides by asking whether any Chrome process still carries our `browser-profile` path on its command line (measured on a machine that also runs an unrelated Chrome: the two sets separate cleanly). Measured latency from closing the window to a full stop is about **5-6 seconds**, after which the previous run's `cmd` and `node` processes are all gone, with no orphans. Two theoretical edges remain: if Chrome keeps a background process alive after the window closes, the service may not stop; and the brief process churn at startup is absorbed by requiring two consecutive empty checks. **`logs\launcher.log` records every decision**, so a failure can be diagnosed.
- **Closing the window immediately kills any task that is running.** That is the intended semantics, but the cost is worth knowing: closing by accident means losing the task.
- **If the supervisor is force-killed** (Task Manager), the server becomes an invisible orphan and closing the window will no longer stop it. Clean up with `stop-dsh.cmd`. (Measured: after killing the supervisor, the server kept running and kept writing files.)
- **Change the default terminal and `dsh-launch.exe` is no longer needed.** If you later set "Default terminal application" to *Windows Console Host*, `-WindowStyle Hidden` works again and that layer can be dropped. Conversely, the reason `dsh-launch.exe` exists at all is Windows Terminal.
- **Taskbar icon (verified)**: the running window really does show the DeepSeek icon, in its own taskbar entry separate from everyday Chrome (confirmed by screenshot, 2026-09-21). Chromium's documentation mentions taskbar icons being "badged with their profile icon"; that does not happen with this "dedicated profile + `--app=`" combination, so the "install as a PWA" route is unnecessary.
- **`pwshPath` is an absolute path and dsh does not verify that it exists.** If that PowerShell 7 directory is deleted or moved, the result is not a fallback to 5.1 but a **shell that does not work at all**. Re-run `setup.ps1` after moving machines or cleaning up disks.
- **Windows only.** No other platform needs these workarounds (the bash executor has no equivalent fallback problem).

---

## References

- [Chromium · Windows Shortcut and Pinned Taskbar Icon handling](https://chromium.googlesource.com/chromium/src/+/main/docs/windows_shortcut_and_taskbar_handling.md)
- [PowerShell 7 releases](https://github.com/PowerShell/PowerShell/releases)
