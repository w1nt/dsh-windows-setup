# DeepSeek Harness · Windows 自包含启动方案

把 DeepSeek Harness 变成一个**像本地应用一样启动与退出、且完全自包含**的 Windows 程序。

实测环境：Windows 11 · Node.js v24 · Chrome / Edge。

**中文** | [English](#english)

**目录**：[特性](#特性) · [前置要求](#前置要求) · [快速开始](#快速开始) · [文件说明](#文件说明) · [目录结构](#运行后的目录结构) · [工作原理](#工作原理) · [注意事项](#注意事项)

**Contents**: [Features](#features) · [Requirements](#requirements) · [Quick start](#quick-start) · [Files](#files) · [Layout](#layout-after-setup) · [How it works](#how-it-works) · [Notes](#notes)

---

## 特性

方案自带一个**原生启动器**与一名**后台守护进程**：前者响应用户的双击，后者管理 harness
服务的完整生命周期——启动服务、打开界面、监视窗口、退出时清理。全部运行时状态集中在
`dsh-home\` 下，整个文件夹因此是自包含的。

- **原生启动** —— 由编译出的启动器响应双击，除 harness 界面外不打开其他窗口
- **独立的界面窗口** —— harness 使用自己的浏览器配置，cookie、历史、任务栏分组都与日常浏览分开
- **生命周期自动管理** —— 关闭界面即停止服务并自行退出；每次启动自动清理上一轮残留
- **随处可用** —— 整个文件夹可复制到任意位置或另一台机器，直接使用
- **日志可追溯** —— 服务输出写入 `logs\`，保留最近 3 轮
- **一个图标启动，一个命令停止** —— 正常停止只需关闭窗口；需要时也可用 `stop-dsh.cmd`
- **免管理员权限** —— 全部安装在用户目录下
- **托管 PowerShell 7** —— 自动安装便携版并接入 harness

---

## 前置要求

- **Windows 10 / 11**
- **Node.js（LTS 版）** —— 必需。确认 `node --version` 和 `npx --version` 都能用
- **Chrome 或 Edge** —— 用于显示界面（Edge 为系统自带）
- **首次运行需要联网** —— 下载 PowerShell 7（约 100 MB）与 harness 本体
- PowerShell 5.1（系统自带，无需额外安装）

> 不需要管理员权限，所有内容都安装在用户目录下。

---

## 快速开始

1. **把整个文件夹复制到想要的位置**，例如 `D:\dsh`。建议使用**纯 ASCII 路径**（不含中文、空格、特殊符号）。

2. **运行一次安装脚本**。在该文件夹中打开 PowerShell：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   它会自动完成：建立目录结构 → 安装便携版 PowerShell 7 → 写入 harness 配置 → 编译启动器 → 创建桌面快捷方式。**可重复运行，不会重复下载。**

3. **双击桌面的「DeepSeek Harness」**。
   首次启动会下载 harness 本体，需要几分钟；之后每次启动都很快。

4. *（可选）* 首次成功启动后，再运行一次：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\make-icon.ps1
   ```

   生成 DeepSeek 图标并应用到桌面快捷方式。

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `dsh-launch.exe` | 桌面快捷方式指向它，原生启动器 |
| `launcher.cs` | 上面那个 exe 的源码，改完重跑 `setup.ps1` 即重新编译 |
| `start-dsh.ps1` | 后台守护进程：启动服务、打开界面、监视窗口、关窗停服 |
| `setup.ps1` | 一次性安装脚本，幂等 |
| `make-icon.ps1` | 可选，生成并应用 DeepSeek 图标 |
| `stop-dsh.ps1` | 手动停止服务（异常时使用） |
| `stop-dsh.cmd` | 上面脚本的双击包装 |
| `README.md` | 本文档 |

---

## 运行后的目录结构

```
<你放的位置>\
├── dsh-launch.exe         # 桌面快捷方式指向它
├── launcher.cs            # 启动器源码
├── start-dsh.ps1          # 后台守护进程
├── setup.ps1
├── make-icon.ps1
├── stop-dsh.ps1
├── stop-dsh.cmd
├── README.md
├── dsh.ico                # make-icon.ps1 生成（可选）
│
├── logs\                  # 运行日志
│   ├── dsh.log                  # 本次运行的服务器输出
│   ├── dsh.1.log / dsh.2.log    # 最近两轮运行
│   └── launcher.log             # 守护进程的运行记录
│
├── run\                   # 运行时状态
│   └── server.pid
│
├── dsh-home\              # 全部运行时状态
│   ├── settings.yaml
│   ├── .credentials.yaml        # 凭据（含 API 密钥）
│   ├── cordis.patch.yml
│   ├── sessions\                # 会话记录
│   ├── storages\
│   ├── npm-cache\
│   └── browser-profile\         # 专属浏览器配置
│
└── dsh-workspace\
```

**整个文件夹就是这套方案的全部**，复制到另一台机器、换个盘符都能直接运行。

- 想彻底重置：删除 `dsh-home`
- 只想清掉浏览器状态：删除 `dsh-home\browser-profile`

---

## 工作原理

```
桌面快捷方式 → dsh-launch.exe        ← 原生启动器，拉起守护进程后立即退出
  └─ start-dsh.ps1                   ← 后台守护进程，随会话常驻
       ├─ 启动本地服务，输出写入 logs\dsh.log
       ├─ 读取认证地址，用专属浏览器窗口打开
       ├─ 持续监视该窗口
       └─ 窗口关闭 → 停止服务 → 自行退出
```

**真正读写文件、执行命令、调用 API 的，是本地的 Node 服务进程**；浏览器窗口只是它的界面。
服务仅绑定回环地址（`127.0.0.1`），不接受局域网访问。

### 日志

| 文件 | 内容 |
|---|---|
| `logs\dsh.log` | 本次运行的服务器输出，每次启动重新开始 |
| `logs\dsh.1.log` / `dsh.2.log` | 最近两轮运行的输出，共保留 3 轮 |
| `logs\launcher.log` | 守护进程的运行记录 |

### 停止

正常方式：**关闭 harness 窗口**。若因异常未能停止，双击 `stop-dsh.cmd`。

---

## 注意事项

- **关闭窗口会立即停止服务**，正在运行的任务也会一并中断
- 仅支持 **Windows**
- `dsh-home\` 内含配置与凭据，其中 `.credentials.yaml` 保存明文 API 密钥，请勿提交到任何仓库

---
---

<a id="english"></a>

# DeepSeek Harness · Windows self-contained launcher

Turn DeepSeek Harness into a Windows program that **starts and stops like a native app, and is fully self-contained**.

Verified on: Windows 11 · Node.js v24 · Chrome / Edge.

[中文](#deepseek-harness--windows-自包含启动方案) | **English**

**Contents**: [Features](#features) · [Requirements](#requirements) · [Quick start](#quick-start) · [Files](#files) · [Layout](#layout-after-setup) · [How it works](#how-it-works) · [Notes](#notes)

---

## Features

The solution ships a **native launcher** and a **background supervisor**: the launcher answers the
double-click, while the supervisor owns the full lifecycle of the harness service - starting it,
opening the interface, watching the window and cleaning up on exit. All runtime state lives under
`dsh-home\`, which is what makes the folder self-contained.

- **Native launch** - a compiled launcher answers the double-click; no window other than the harness interface itself is opened
- **An interface of its own** - the harness uses a dedicated browser profile, so cookies, history and taskbar grouping stay apart from your everyday browsing
- **Managed lifecycle** - closing the interface stops the service and exits; each start clears whatever the previous run left behind
- **Portable** - the whole folder can be copied anywhere, or to another machine, and simply runs
- **Traceable** - service output is written to `logs\`, keeping the last 3 runs
- **One icon to start, one command to stop** - closing the window is the normal stop; `stop-dsh.cmd` is there when you need it
- **No administrator rights** - everything installs under your user profile
- **PowerShell 7 included** - a portable copy is installed and wired into the harness automatically

---

## Requirements

- **Windows 10 / 11**
- **Node.js (LTS)** - required. Confirm both `node --version` and `npx --version` work
- **Chrome or Edge** - used to display the interface (Edge ships with Windows)
- **Internet access on first run** - to download PowerShell 7 (~100 MB) and the harness itself
- PowerShell 5.1 (built into Windows; nothing to install)

> No administrator rights. Everything installs under your user profile.

---

## Quick start

1. **Copy the whole folder wherever you want it**, for example `D:\dsh`. An **ASCII-only path** (no non-ASCII characters, spaces or symbols) is recommended.

2. **Run the setup script once.** Open PowerShell in that folder:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   It builds the layout, installs portable PowerShell 7, writes the harness config, compiles the launcher and creates the desktop shortcut. **Safe to re-run; it will not download twice.**

3. **Double-click "DeepSeek Harness" on your desktop.**
   The first launch downloads the harness and takes a few minutes; later launches are quick.

4. *(Optional)* After the first successful launch, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\make-icon.ps1
   ```

   It builds a DeepSeek icon and applies it to the desktop shortcut.

---

## Files

| File | Purpose |
|---|---|
| `dsh-launch.exe` | What the desktop shortcut runs: a native launcher |
| `launcher.cs` | Source of that exe; edit it and re-run `setup.ps1` to rebuild |
| `start-dsh.ps1` | The background supervisor: starts the service, opens the window, watches it, stops on close |
| `setup.ps1` | One-time setup, idempotent |
| `make-icon.ps1` | Optional: builds and applies the DeepSeek icon |
| `stop-dsh.ps1` | Manual stop, for the abnormal case |
| `stop-dsh.cmd` | Double-click wrapper around the script above |
| `README.md` | This document |

---

## Layout after setup

```
<wherever you put it>\
├── dsh-launch.exe         # what the desktop shortcut runs
├── launcher.cs            # launcher source
├── start-dsh.ps1          # background supervisor
├── setup.ps1
├── make-icon.ps1
├── stop-dsh.ps1
├── stop-dsh.cmd
├── README.md
├── dsh.ico                # built by make-icon.ps1 (optional)
│
├── logs\                  # run logs
│   ├── dsh.log                  # server output, current run
│   ├── dsh.1.log / dsh.2.log    # the two previous runs
│   └── launcher.log             # the supervisor's own record
│
├── run\                   # runtime state
│   └── server.pid
│
├── dsh-home\              # all runtime state
│   ├── settings.yaml
│   ├── .credentials.yaml        # credentials (holds your API key)
│   ├── cordis.patch.yml
│   ├── sessions\                # session transcripts
│   ├── storages\
│   ├── npm-cache\
│   └── browser-profile\         # the dedicated browser profile
│
└── dsh-workspace\
```

**That folder is the entire setup.** Copy it to another machine or another drive and it runs.

- Full reset: delete `dsh-home`
- Reset only the browser state: delete `dsh-home\browser-profile`

---

## How it works

```
desktop shortcut -> dsh-launch.exe     <- native launcher; starts the supervisor and exits
  └─ start-dsh.ps1                     <- background supervisor, resident for the session
       ├─ starts the local service, output goes to logs\dsh.log
       ├─ reads the authenticated URL and opens it in the dedicated browser window
       ├─ keeps watching that window
       └─ window closed -> stops the service -> exits
```

**The process that reads and writes files, runs commands and calls the API is the local Node service**;
the browser window is only its interface. The service binds the loopback address only (`127.0.0.1`)
and is not reachable from the LAN.

### Logs

| File | Contents |
|---|---|
| `logs\dsh.log` | Server output for the current run; fresh on every start |
| `logs\dsh.1.log` / `dsh.2.log` | The two previous runs; 3 runs are kept in total |
| `logs\launcher.log` | The supervisor's own record |

### Stopping

Normal: **close the harness window**. If it fails to stop for any reason, double-click `stop-dsh.cmd`.

---

## Notes

- **Closing the window stops the service immediately**, and any task still running is interrupted with it
- **Windows only**
- `dsh-home\` holds your configuration and credentials; `.credentials.yaml` stores your API key in plain text, so never commit it to any repository
