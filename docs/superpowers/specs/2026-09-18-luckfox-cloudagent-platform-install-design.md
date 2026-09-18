# Luckfox Pico Cloud Agent 平台安装与启动顺序设计规格（Design Spec）

- **日期**：2026-09-18
- **状态**：已 Review
- **分支**：`cursor/platform-install-spec-8f0d`（起点 `origin/dev`）
- **主题**：把 Cursor 平台在 Environment Build 与 Agent Run 中实际执行的命令层顺序写成活目录，并与仓库 Dockerfile / `install.sh` / `start.sh` 分层对齐
- **关联代码文件**：不改运行时文件。分层上下文见 `.cursor/environment.json`、`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`.cursor/install.sh`、`.cursor/start.sh`
- **关联计划**：[`2026-09-18-luckfox-cloudagent-platform-install.md`](../plans/2026-09-18-luckfox-cloudagent-platform-install.md)
- **关联规格**：[`2026-07-13-luckfox-cloudagent-env-design.md`](2026-07-13-luckfox-cloudagent-env-design.md)、[`2026-08-30-luckfox-cloudagent-tailscale-design.md`](2026-08-30-luckfox-cloudagent-tailscale-design.md)、[`2026-09-14-luckfox-cloudagent-default-user-design.md`](2026-09-14-luckfox-cloudagent-default-user-design.md)、[`2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md`](2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md)

---

## 1. 概述与目标

仓库 Dockerfile 注释框、[`2026-08-30` §2.3](2026-08-30-luckfox-cloudagent-tailscale-design.md)、[`2026-08-30` plan「Environment Build install 流水」](../plans/2026-08-30-luckfox-cloudagent-tailscale.md)、[`2026-08-30` §4.4](2026-08-30-luckfox-cloudagent-tailscale-design.md) 与 [`2026-09-14` §2.4](2026-09-14-luckfox-cloudagent-default-user-design.md) 分别记下平台 Aptfile、分层、一次 Build 时间表、VNC 运行时与进程属主。本规格把 **Environment Build 命令顺序** 与 **Agent Run 命令层** 收成一份活目录，避免把现行顺序塞进 08-30 plan 的历史表，或把 `desktop-init.sh` 误当成装包脚本。分层、冻结范围与文档边界见 §2 与 F1–F5。

**不在本规格范围**：改 `.cursor/Dockerfile*` / `install.sh` / `start.sh` / `environment.json` / `AGENTS.md`；把桌面栈写进本仓 Dockerfile；按 Aptfile「已有就不写」省略 Dockerfile apt；还原 `podConfig.ts`；把 Docker 引擎写入本仓 Dockerfile。

---

## 2. 设计决策

### 2.1 落点：新 spec 作活目录

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| A. 新 spec（采用） | 本文件收现行 Build/Run 命令层、脚本路径、Aptfile 清单与 09-06/09-16 差 | 活目录与 08-30 历史时间表分离；07-13 / 08-30 只在合入时加指针 |
| B. 扩写 08-30 spec §2.3 | 把平台命令表写进 Tailscale 分层章 | 否决。§2.3 管 Dockerfile / install / start 职责，不是平台命令目录 |
| C. 改写 08-30 plan 流水为活目录 | 用 09-16 数字覆盖 09-06 表 | 否决。该表是 `bld-20260906-a344b2e4-…` 的墙钟与磁盘增量 |
| D. 扩写 07-13 交付物 | 在环境 spec 枚举平台命令 | 否决。07-13 管配置即代码与编译路径 |

合入时 plan 只在三处加指针，不把命令表抄过去：08-30 spec §2.3 平台 Aptfile 行、08-30 plan「Environment Build install 流水」引言、07-13 §10 交付物。

### 2.2 Environment Build 只落盘；Agent Run 才保进程

Environment Build：Docker 镜像 → 工作区 clone → 平台 install 命令 → 仓库 `install.sh` → snapshot。Build 日志里的 `start:core-dumps` / `start:desktop-init` / `start:exec-daemon` 是 **install pod 内 detached 拉起**，不进入快照进程表。Agent Run 从 snapshot 冷启动后再拉起命令层服务。User Secrets 只在 Run 注入。不得把 detached `start:*` 当成 snapshot 常驻进程，也不得把 `start.sh` 写入 Build 目录。

### 2.3 分发器脚本 vs 控制器注入命令

平台桌面装包入口是 `/opt/cursor/cloud-agent-tools/current/cloud-agent-setup`（`sync-assets` / `run-step` / `wrap-vnc-step`）。`run-step` 只调度 §3.4 列出的那些步骤；捆绑源在 `files/vnc/` 与 `files/anyos/`，运行时副本在 `/usr/local/bin/*`、`/usr/local/share/desktop-init.sh`、`/tmp/capture-vnc-user-env`。

`configure-git`、`link-gh-to-usr-local-bin`、`create-artifacts-dir`、`create-exec-daemon-dir`、`install-agent-store-fuse`、`install-exec-daemon`、`start:core-dumps` **不在** `cloud-agent-setup` 的 `run-step` case 里，本 VM 也没有对应 on-disk 安装脚本（分发器注释写明须与 `packages/agent-controller/src/podConfig.ts` 对齐，该文件不在本仓）。本规格只记 Build 命令名与磁盘可见产物，不编造脚本正文。

### 2.4 `desktop-init.sh` 是运行时入口

`/usr/local/share/desktop-init.sh`（394 行，sha256 `4f8d5598ca29964beb4fa63587d204dda8f9a89a3700eb59a51f7961615df7ad`，与 2026-08-29 相同）由 `start:desktop-init` 拉起，读 `/tmp/vnc-desktop-user-env` 与 `/usr/local/share/anyos.conf`，再启动 TigerVNC / XFCE / noVNC。它 **不** `apt-get`、**不**写 Aptfile。子进程、端口与 `-localhost` 约束见 08-30 §4.4；属主见 09-14 §2.4。

### 2.5 时间表冻结；现行顺序用 09-16

08-30 plan 流水表冻结为 2026-09-06（`bld-20260906-a344b2e4-98f2-411d-86fa-d45b6dfa20cb`，Chrome `152.0.7977.82-1`，VNC apt 13 升级 + 408 新装）。现行命令名与差量以 2026-09-16 active Build [`bld-20260916-1810ec4f-7cfd-4098-8b47-2d234582e1a6`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260916-1810ec4f-7cfd-4098-8b47-2d234582e1a6) 为准（Chrome `153.0.8010.47-1`，VNC apt 13 升级 + 406 新装）。Aptfile 58 个名字与 sha256 `819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8` 两次相同。406 相对 408 少 2 个新装，是因为活动 Dockerfile 已含 2026-09-16 诊断 CLI，传递依赖不再由 Aptfile 那次 apt 计入。

### 2.6 文档边界

两份 Dockerfile 顶部 Aptfile 注释框保持原样（含「另外平台还会…」那一行）。该行不是活目录：未列出 `configure-git` 以外的控制器命令，也把 `git clean -fd` 写成「每次启动」，与 Build 期 `configure-git` 的 `git-cleanup` 子步骤不是同一层。`AGENTS.md` 只保留 Aptfile 一句，不扩写命令表。Dockerfile apt 取舍仍只看 FROM digest 的 dpkg（08-30 §2.3.1），**不得**因 Aptfile 已有同名包而从 Dockerfile 省略。

---

## 3. 命令层顺序

### 3.1 分层

| 层 | 何时 | 内容 |
| --- | --- | --- |
| 公开 Dockerfile | Environment Build 镜像 | SDK/工具 apt、Tailscale 包、sudoers、`git safe.directory`、`USER ubuntu`；不装 `openssh-server` |
| 平台 Aptfile + `cloud-agent-setup` | Dockerfile 之后、仓库 `install.sh` 之前 | 写入 Aptfile 与桌面脚本；按 Aptfile `--no-install-recommends` 装 58 包；`install-google-chrome` 另装 Chrome |
| 控制器注入命令 | 同上阶段，无本仓脚本 | exec-daemon、git 身份/签名、`gh` 软链、artifacts / exec-daemon 目录、fuse 二进制；Build pod 内 detached `start:*` |
| `.cursor/install.sh` | 平台命令之后、snapshot 之前 | grilling skill + 私有快照 `openssh-server` + host key stamp（08-30 §2.3–§2.4） |
| Agent Run 命令层 | 每个 Run | `tini` → `pod-daemon` → `start:core-dumps` / `start:desktop-init` / `start:exec-daemon` → fuse 挂载 → `start.sh` |
| `.cursor/start.sh` | Run，JSON `sudo -n -E` | forwarding、`tailscaled`、`up`、Serve 5901/1054/1055、sshd `:22`（08-30 §2.2–§2.6） |

### 3.2 Environment Build（现行顺序，2026-09-16）

命令名来自该次 Build 日志的 `[INSTALL] Command:` / `[SPAN] start:*`。SDK/Tailscale 层为 cache hit。复现：对同一 `buildId` 取 install 日志，按下列名字核对顺序。

| 顺序 | 命令 | 做什么 |
| --- | --- | --- |
| 1 | Docker clone → `dockerBuild` | `FROM ubuntu:24.04@sha256:4fbb8e6a…`；SDK+诊断 CLI apt；Tailscale；sudoers；`git safe.directory` |
| 2 | Workspace clone | install 阶段工作树 |
| 3 | `install-exec-daemon` | 写入 `/exec-daemon`（控制器；无分发器脚本） |
| 4 | `install-cloud-agent-assets` | 升级 `coreutils`/`gzip`/`tar`；安装捆绑工具与 Aptfile；拉字体/主题等资产 |
| 5 | `capture-vnc-user-env` | 写 `/tmp/vnc-desktop-user-env`（用户名与 `HOME`） |
| 6 | `install-vnc-desktop-apt-packages` | 按 Aptfile 安装；该次 13 升级 + 406 新装 |
| 7 | `install-google-chrome` | `google-chrome-stable` `153.0.8010.47-1`（不在 Aptfile） |
| 8 | `configure-google-chrome` | Chrome 策略 |
| 9 | `install-locales` | `locale-gen en_US.UTF-8` |
| 10 | `cleanup-vnc-desktop-apt` | apt 清理 |
| 11 | `install-fonts-and-fontconfig` | `fc-cache` |
| 12 | `install-and-configure-themes` | WhiteSur 等 |
| 13 | `install-remote-vnc-setup` | 远程 VNC 脚本 |
| 14 | `configure-os-display` | 1920×1200 @ 96 DPI（`anyos.conf`） |
| 15 | `install-cursor-artifact-directories` | `/opt/cursor`、`/opt/cursor/artifacts`、`/opt/cursor/recording-staging` mode 777 |
| 16 | `configure-git` | 日志子步骤 `git-config-setup` / `git-cleanup` / `token-refresh`；磁盘可见 `user.name=Cursor Agent`、`user.email=cursoragent@cursor.com`、`gpg.format=ssh`、`commit.gpgsign=true`、`gpg.ssh.program=/home/ubuntu/.cursor/bin/cursor-git-ssh-keygen`。不记录密钥或 token |
| 17 | `link-gh-to-usr-local-bin` | `/usr/local/bin/gh` → `/exec-daemon/gh` |
| 18 | `create-artifacts-dir` | 无 on-disk 脚本；与 15 分工以平台为准 |
| 19 | `create-exec-daemon-dir` | 无 on-disk 脚本；`/exec-daemon` 目录 |
| 20 | `install-agent-store-fuse` | 安装 `/usr/local/bin/cursor-agent-store-fuse` |
| 21 | detached `start:core-dumps` / `start:desktop-init` / `start:exec-daemon` | 仅 Build pod；不进入 snapshot 进程表 |
| 22 | `.cursor/install.sh` | grilling + `openssh-server`（该次 2 升级 + 42 新装）；`policy-rc.d` 禁止启动 sshd |
| 23 | snapshot | 该次随后 Warming complete |

### 3.3 Agent Run（命令层）

现行会话绑定上述 snapshot，冷启动（`gitSetup=reuse`）。命令层如下；不在此枚举 XFCE 子进程。

| 顺序 | 命令 / 进程 | 属主 | 作用 |
| --- | --- | --- | --- |
| 1 | `tini`（PID 1）→ `pod-daemon` | root | 容器 init 与 Pod 控制面 |
| 2 | `start:core-dumps` | 平台 | 无本仓脚本 |
| 3 | `start:desktop-init` → `/usr/local/share/desktop-init.sh` | ubuntu | 拉起 VNC/XFCE/noVNC；子进程见 08-30 §4.4、09-14 §2.4 |
| 4 | `start:exec-daemon` | ubuntu `node`，父进程 `pod-daemon` | 终端 / PTY；二进制在 `/exec-daemon` |
| 5 | fuse | ubuntu | `cursor-agent-store-fuse` 挂载 `/cursor/stores`（`fuse.agent-store`）；`/run/agent-store-fuse/self-store-id` 供 `start.sh` 解析 bcId；Run 上 `/opt/cursor/artifacts` → `/cursor/stores/self/artifacts` |
| 6 | `.cursor/start.sh` | root（JSON `sudo -n -E`） | Tailscale + sshd；细节不在本文件重复 |

`desktop-init` 与 `start.sh` 并行于平台 start 阶段，不是互相的父进程：`desktop-init.sh` 与 `tailscaled` / `sshd` 的 PPID 均为 `tini`。

### 3.4 `/opt/cursor/` 树与职责

平台桌面工具包与 artifacts 根在 `/opt/cursor/`。复现：`tree /opt/cursor`（不加 `-a`）。现行 snapshot（`bld-20260916-1810ec4f-…`）输出 10 directories、18 files：

```
/opt/cursor
├── artifacts -> /cursor/stores/self/artifacts
├── cloud-agent-tools
│   ├── c06a0611e1e6a422d86412295478c5681504707a103c16b3b20ef457374da371
│   │   ├── cloud-agent-assets.tsv
│   │   ├── cloud-agent-setup
│   │   ├── cloud-agent-tools.tsv
│   │   └── files
│   │       ├── anyos
│   │       │   ├── anyos-setup.sh
│   │       │   └── anyos.conf
│   │       └── vnc
│   │           ├── capture-vnc-user-env.sh
│   │           ├── configure-google-chrome.sh
│   │           ├── configure_os_display.sh
│   │           ├── desktop-init.sh
│   │           ├── install-cursor-artifact-directories.sh
│   │           ├── install-fonts-and-fontconfig.sh
│   │           ├── install-google-chrome.sh
│   │           ├── install-locales.sh
│   │           ├── install-remote-vnc-setup.sh
│   │           ├── install-vnc-desktop-apt-packages.sh
│   │           ├── install_and_configure_themes.sh
│   │           └── vnc-desktop.Aptfile
│   ├── current -> /opt/cursor/cloud-agent-tools/c06a0611e1e6a422d86412295478c5681504707a103c16b3b20ef457374da371
│   └── current.bundle-hash
├── logs
└── recording-staging
```

`current` 与 `current.bundle-hash` 都指向同一内容寻址目录名 `c06a0611…`。`install-cloud-agent-assets` 按 `cloud-agent-tools.tsv`（14 行）把捆绑文件装到 `/usr/local` 或 `/tmp`，源文件仍留在本树。`tree` 默认不列出点目录；另有 `/opt/cursor/.exec-daemon/`（exec-daemon 请求上下文缓存，不是安装脚本，不展开文件正文）。

| 路径 | 用途 | 运行时副本 / 备注 |
| --- | --- | --- |
| `/opt/cursor/artifacts` | Agent 产物目录 | Run 上软链到 `/cursor/stores/self/artifacts`（fuse） |
| `/opt/cursor/logs` | 平台日志目录 | 现行空 |
| `/opt/cursor/recording-staging` | 录像暂存 | `install-cursor-artifact-directories` 创建，mode 777；现行空 |
| `cloud-agent-tools/current` | 现行工具包 | 软链到内容寻址目录 |
| `current.bundle-hash` | 现行捆绑哈希 | 与目录名相同 |
| `cloud-agent-setup` | Build 分发器 | `sync-assets` / `run-step` / `wrap-vnc-step` |
| `cloud-agent-tools.tsv` | 捆绑工具清单 | 源路径与安装目标（base64） |
| `cloud-agent-assets.tsv` | 远程资产清单 | 31 行；字体、图标、WhiteSur、noVNC/websockify zip 等，由 `sync-assets` 下载 |
| `files/anyos/anyos.conf` | 桌面分辨率 / DPI / 字体 | `/usr/local/share/anyos.conf`；现行 1920×1200 @ 96 DPI |
| `files/anyos/anyos-setup.sh` | 把 conf 套进 XFCE/GTK/Plank 模板 | `/usr/local/bin/anyos-setup`；**不在** `run-step` case |
| `files/vnc/vnc-desktop.Aptfile` | 58 包清单（§4） | `/usr/local/share/vnc-desktop.Aptfile` |
| `files/vnc/capture-vnc-user-env.sh` | 记录 VNC 用户名与 `HOME` | `/tmp/capture-vnc-user-env` → `/tmp/vnc-desktop-user-env` |
| `files/vnc/install-vnc-desktop-apt-packages.sh` | 按 Aptfile `apt-get install --no-install-recommends` | `/usr/local/bin/install-vnc-desktop-apt-packages` |
| `files/vnc/install-google-chrome.sh` | 加 Google apt 源并装 `google-chrome-stable` | `/usr/local/bin/install-google-chrome`；Chrome 不在 Aptfile |
| `files/vnc/configure-google-chrome.sh` | 写用户 Chrome 配置与 `.desktop` 启动参数（软件 GL、无沙箱） | `/usr/local/bin/configure-google-chrome` |
| `files/vnc/install-locales.sh` | 启用并 `locale-gen en_US.UTF-8` | `/usr/local/bin/install-locales` |
| `files/vnc/install-fonts-and-fontconfig.sh` | 安装捆绑 Cascadia 等并写 fontconfig | `/usr/local/bin/install-fonts-and-fontconfig` |
| `files/vnc/install_and_configure_themes.sh` | 解压 WhiteSur GTK/图标/光标 | `/usr/local/bin/install-and-configure-themes` |
| `files/vnc/install-remote-vnc-setup.sh` | 解压捆绑 noVNC 1.2.0 与 websockify 0.10.0 | `/usr/local/bin/install-remote-vnc-setup` |
| `files/vnc/configure_os_display.sh` | 按 `anyos.conf` 写 XFCE/终端/GTK 显示配置 | `/usr/local/bin/configure-os-display` |
| `files/vnc/install-cursor-artifact-directories.sh` | 创建 `/opt/cursor`、`artifacts`、`recording-staging` | `/usr/local/bin/install-cursor-artifact-directories` |
| `files/vnc/desktop-init.sh` | Run 桌面入口（§2.4） | `/usr/local/share/desktop-init.sh` |

`cloud-agent-setup run-step` 已知步骤：`capture-vnc-user-env`、`install-vnc-desktop-apt-packages`、`install-google-chrome`、`configure-google-chrome`、`install-locales`、`cleanup-vnc-desktop-apt`、`install-fonts-and-fontconfig`、`install-and-configure-themes`、`install-remote-vnc-setup`、`configure-os-display`、`install-cursor-artifact-directories`。`cleanup-vnc-desktop-apt` 在分发器内联，无独立捆绑脚本。

不在本树、由控制器注入的可见产物：`/home/ubuntu/.cursor/bin/cursor-git-ssh-keygen`（`gpg.ssh.program`）、`/usr/local/bin/gh` → `/exec-daemon/gh`、`/usr/local/bin/cursor-agent-store-fuse`。

---

## 4. Aptfile 清单

文件 `/usr/local/share/vnc-desktop.Aptfile`，sha256 `819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8`，**58** 个包名（去掉注释与空行）。`install-vnc-desktop-apt-packages` 以 `apt-get install -y --no-install-recommends` 一次装完。Chrome 不在此文件。

| 组 | 包 |
| --- | --- |
| VNC | `tigervnc-standalone-server` `tigervnc-common` `tigervnc-tools` |
| XFCE | `xfce4` `xfce4-terminal` `xfce4-settings` `thunar` |
| X11 | `x11-utils` `x11-xserver-utils` `xdg-utils` `xdotool` `xclip` `procps` |
| D-Bus | `dbus-x11` `at-spi2-core` |
| 应用 | `mousepad` `seahorse` `sudo` `ffmpeg` |
| 主题 | `adwaita-icon-theme` `gnome-themes-extra` `gnome-keyring` `plank` `sassc` `libglib2.0-dev-bin` `libxml2-utils` `dconf-cli` `xz-utils` |
| locale | `locales` |
| 字体 | `fonts-noto` `fonts-wqy-microhei` `fonts-droid-fallback` `fonts-noto-color-emoji` `fonts-liberation` `fonts-croscore` `fonts-cantarell` `fonts-jetbrains-mono` `xfonts-base` `xfonts-terminus` |
| 桌面库 | `libx11-dev` `libxkbfile-dev` `libsecret-1-dev` `libgbm-dev` `libnotify4` `libnss3` `libxss1` `libgl1-mesa-dri` `libglx-mesa0` `libgl1` |
| Python | `python3-minimal` `python3-numpy` |
| 资产依赖 | `bash` `ca-certificates` `coreutils` `curl` `findutils` `gzip` `tar` |

复现：`sha256sum /usr/local/share/vnc-desktop.Aptfile`；`grep -vE '^#|^$' /usr/local/share/vnc-desktop.Aptfile | wc -l`。

---

## 5. 需求

### 5.1 功能需求

| 编号 | 需求 |
| --- | --- |
| F1 | 本文件是平台 Build/Run 命令层的活目录；08-30 plan 流水表保持 2026-09-06 历史证据 |
| F2 | Run 只写 §3.3 命令层；desktop-init 子进程用指针，不在此复制进程全表 |
| F3 | 不修改两份 Dockerfile、`AGENTS.md`、`environment.json`、`install.sh`、`start.sh` |
| F4 | Review 后的 plan 只改 08-30 spec §2.3、08-30 plan 流水引言、07-13 §10，加指向本文件的指针 |
| F5 | 控制器注入命令只记命令名与可见产物，不编造 `podConfig.ts` 脚本 |

### 5.2 非功能需求

| 编号 | 需求 |
| --- | --- |
| N1 | 不写入 Secret、token、私钥、签名公钥 |
| N2 | 正文只留现行结论与可复现依据；不写修订过程 |
| N3 | 不把平台 Aptfile 当作 Dockerfile apt 取舍依据 |

---

## 6. 验证策略

本规格是文档。V1–V4 用当前 Agent 与 09-16 Build 日志核对；V5 在 plan 落地指针后做。

| 步骤 | 通过标准 |
| --- | --- |
| V1 | 本文件路径存在，状态为已 Review，关联计划已写成正文 |
| V2 | 相对本功能起点，`.cursor/Dockerfile*`、`AGENTS.md`、`environment.json`、`install.sh`、`start.sh` 无 diff |
| V3 | Aptfile sha256 与 58 个名字与 §4 一致 |
| V4 | 09-16 Build 日志的 `[INSTALL] Command:` 顺序与 §3.2 命令名一致 |
| V5 | plan 三处指针指向本文件，且不改写 08-30 plan 09-06 数字 |

---

## 7. 风险与约束

| 风险 | 缓解 |
| --- | --- |
| 把 `desktop-init.sh` 当成装包脚本 | §2.4：它只拉起桌面；apt 在 Build 的 Aptfile 步骤 |
| 用 09-16 覆盖 08-30 plan 时间表 | §2.5 / F1：流水表冻结；差量只写本文件 |
| 按 Aptfile 省略 Dockerfile 包 | §2.6 / N3：写入集合只看 FROM dpkg |
| 为补注释框而改 Dockerfile | Q4 / F3：注释框冻结 |
| 把 Build pod 的 detached `start:*` 当成 snapshot 常驻进程 | §2.2：Run 才保进程 |
| 从残留文件还原控制器脚本 | §2.3 / F5：只记命令名与产物 |

---

## 8. QA 记录

本节只收录 grilling 已闭合的决策；同一主题并入原条目、不新开编号。

| ID | 问题 | 用户选择 | 备注 |
| --- | --- | --- | --- |
| Q1 | 活目录写到哪 | 新 spec，不把现行顺序塞进 07-13 / 08-30 spec 或 08-30 plan | 见 §2.1 |
| Q2 | Agent Run 是否只写 `start.sh` + `desktop-init` | 否。命令层为 `tini`/`pod-daemon`、`start:core-dumps`、`desktop-init`、`exec-daemon`、fuse、`start.sh`；子进程用既有 spec 指针 | 见 §2.4、§3.3 |
| Q3 | 08-30 plan 流水与 Dockerfile 注释框 | 冻结 2026-09-06 时间表；不改注释框；合入时只在 §2.1 三处加指针 | 见 §2.5、§2.6 |
| Q4 | 是否改 Dockerfile | 不改 | 见 F3 |
| Q5 | 是否改 `AGENTS.md` | 不改 | 见 F3 |
| Q6 | 是否写 plan | 要。先本 spec，Review 后再按 spec 写 plan | 见关联计划 |

---

## 9. 后续

实现步骤与指针落地见 [`2026-09-18-luckfox-cloudagent-platform-install.md`](../plans/2026-09-18-luckfox-cloudagent-platform-install.md)。
