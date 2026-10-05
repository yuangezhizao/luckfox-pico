# Luckfox Pico Cloud Agent 平台安装与启动顺序设计规格（Design Spec）

- **日期**：2026-09-18
- **状态**：已 Review
- **分支**：`cursor/platform-install-spec-8f0d`（起点 `origin/dev`）
- **主题**：说明 Cursor 平台与本仓配置在 Environment Build 和 Agent Run 中各做什么、如何衔接
- **基线**：Environment Build `bld-20261003-4581ee1c-6629-4038-965b-04fde88b37a1`（2026-10-03）；运行时部分于 2026-10-05 在当前 Agent 上复核，该 Agent 的磁盘内容与这次 Build 一致
- **平台明细**：[Cursor-Cloud-Agents @ `db82179`](https://github.com/yuangezhizao/Cursor-Cloud-Agents/tree/db8217941c3f4d017a0ec5098e7603d402aefeb3)，按文件收录平台 18 个安装步骤写入的内容
- **关联代码文件**：`.cursor/environment.json`、`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`.cursor/install.sh`、`.cursor/start.sh`（本规格只改两份 Dockerfile 的注释）
- **关联计划**：[`2026-09-18-luckfox-cloudagent-platform-install.md`](../plans/2026-09-18-luckfox-cloudagent-platform-install.md)
- **关联规格**：[`2026-07-13-luckfox-cloudagent-env-design.md`](2026-07-13-luckfox-cloudagent-env-design.md)、[`2026-08-30-luckfox-cloudagent-tailscale-design.md`](2026-08-30-luckfox-cloudagent-tailscale-design.md)、[`2026-09-14-luckfox-cloudagent-default-user-design.md`](2026-09-14-luckfox-cloudagent-default-user-design.md)、[`2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md`](2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md)

---

## 1. 概述与目标

Cloud Agent 的环境由两部分叠加而成：一部分由本仓的 `environment.json`、Dockerfile、`install.sh` 和 `start.sh` 定义，另一部分是 Cursor 平台在 Build 和 Run 中自动执行的步骤。平台这部分不在本仓，相关认识原本散落在 Dockerfile 注释框、08-30 spec §2.3 与 §4.4、08-30 plan 的 09-06 Build 时间表和 09-14 spec §2.4 中，口径不一，也产生过几处误读（§8）。

本规格把两部分放到同一条时间线上，回答四个问题：

1. Environment Build 依次做什么，哪些步骤属于本仓、哪些属于平台（§2）；
2. Agent Run 时有哪些常驻进程，由谁拉起、以什么身份运行（§3）；
3. `/opt/cursor/` 下的文件各有什么用（§4）；
4. 环境里的 apt 包从哪里来，平台 Aptfile 只占其中哪一部分（§5）。

平台 18 个安装步骤的逐步明细和写入的文件由 Cursor-Cloud-Agents 仓库维护。本规格引用它的固定提交，不再复制一份（§6.1）。

**不在本规格范围**：修改 Dockerfile 构建指令、`environment.json`、`install.sh`、`start.sh`；把桌面栈写进本仓镜像；还原平台控制器的源码；排查 `/cursor/stores` 的 FUSE 访问故障。

---

## 2. Environment Build

以 2026-10-03 这次 Build 为例，顺序如下：

```text
docker build（本仓 Dockerfile）
  → 检出工作区
  → 平台安装（18 个步骤）
  → 平台以 detached 方式拉起 start:core-dumps / start:desktop-init / start:exec-daemon
  → 本仓 .cursor/install.sh
  → 生成快照
```

**本仓 Dockerfile** 安装 SDK 编译依赖、诊断工具和 Tailscale，配置 `ubuntu` 免密 sudo 与 `git safe.directory`，最后切换到 `USER ubuntu`。`openssh-server` 不在公开镜像层安装。这次 Build 中，SDK 与 Tailscale 两层直接命中了构建缓存。

**平台安装**的 18 个步骤按执行方式分为两类：

- `install-cloud-agent-assets` 安装平台工具包（`/opt/cursor/cloud-agent-tools`），并下载字体、主题等资产。随后 11 个桌面相关步骤由工具包中的 `cloud-agent-setup run-step` 执行：记录 VNC 用户、按 Aptfile 安装桌面包、安装并配置 Chrome，以及 locale、字体、主题、noVNC、显示参数和 artifacts 目录。这些脚本都能在 `/opt/cursor/` 下找到（§4）。
- 另外 6 步由平台控制器直接下发，VM 里没有对应的脚本：`install-exec-daemon`、`configure-git`、`link-gh-to-usr-local-bin`、`create-artifacts-dir`、`create-exec-daemon-dir`、`install-agent-store-fuse`。它们留下的可见产物有 `/exec-daemon`、git 身份与 SSH 提交签名配置、`/usr/local/bin/gh` 链接、`/opt/cursor/.exec-daemon` 目录和 FUSE 组件。本规格只记录命令名和这些产物，不推测脚本内容。

每一步的时间窗和写入路径见 Cursor-Cloud-Agents 规格的 [§4.0.3](https://github.com/yuangezhizao/Cursor-Cloud-Agents/blob/db8217941c3f4d017a0ec5098e7603d402aefeb3/docs/superpowers/specs/2026-10-04-cloudagent-env-snapshot-design.md)。

**detached 的 `start:*`**：平台安装结束后，三个 `start:*` 命令在同一秒被拉起，然后才执行本仓 `install.sh`。这些进程只存在于 Build pod 中。快照保存的是磁盘而不是进程，Run 中看到的 exec-daemon 和 desktop-init 都是重新启动的。

**本仓 `install.sh`** 下载 grilling skill，安装 `openssh-server`，并在没有 stamp 时轮换 host key，使 host key 只进入私有快照（08-30 spec §2.3–§2.4）。之后平台生成快照。

本仓使用的两个 User Secrets（`TAILSCALE_AUTHKEY`、`SSH_AUTHORIZED_KEYS`）只在 Agent Run 时注入，由同样在 Run 中执行的 `start.sh` 使用；这不代表其他类型的 Secrets 在 Build 中不可用。

---

## 3. Agent Run

Agent 从快照启动后，平台拉起常驻服务，本仓 `start.sh` 也在这时运行。2026-10-05 在当前 Agent 上看到的进程关系如下：

```text
tini（PID 1，root）
├── pod-daemon（root）
│   ├── exec-daemon：/exec-daemon/node（ubuntu）
│   └── cursor-agent-store-fuse（ubuntu），挂载 /cursor/stores
├── desktop-init.sh（ubuntu）→ TigerVNC / XFCE / noVNC
├── tailscaled（root）
└── sshd（root）
```

- **exec-daemon** 由 `start:exec-daemon` 拉起，提供终端、PTY 和命令执行。
- **desktop-init.sh** 是 `start:desktop-init` 的运行时入口。它读取 `/tmp/vnc-desktop-user-env` 与 `/usr/local/share/anyos.conf` 后启动桌面，不调用 apt，也不读写 Aptfile。其子进程和端口见 08-30 spec §4.4，进程身份见 09-14 spec §2.4。
- **cursor-agent-store-fuse** 把 `/cursor/stores` 挂载为 `fuse.agent-store`。Run 中的 `/opt/cursor/artifacts` 是指向 `/cursor/stores/self/artifacts` 的链接。`start.sh` 在没有 `CURSOR_CONVERSATION_ID` 时，从 `/run/agent-store-fuse/self-store-id` 读取会话 ID 来生成 Tailscale 主机名。
- **tailscaled 与 sshd** 由 `start.sh` 以 root（`sudo -n -E`）启动。脚本配置完成后退出，这两个进程由 tini 接管，所以父进程显示为 tini。细节见 08-30 spec §2.2–§2.6。

`start:core-dumps` 在 Run 中没有对应的常驻进程。上面的进程树只是复核那一刻的状态，启动先后的问题见 §7。

---

## 4. `/opt/cursor/` 目录

Run 中 `tree /opt/cursor` 的输出如下（不含隐藏目录）：

```text
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

`cloud-agent-tools/` 下是内容寻址的平台工具包：目录名就是捆绑哈希，`current` 链接和 `current.bundle-hash` 都指向它。`cloud-agent-setup` 是分发器，提供 `sync-assets`、`run-step` 和 `wrap-vnc-step` 三个子命令。`cloud-agent-assets.tsv` 列出从远端下载的 31 项资产，包括字体、图标、WhiteSur 主题和 noVNC / websockify 压缩包。`cloud-agent-tools.tsv` 列出 14 个捆绑文件及其安装位置：

| 工具包内文件 | 安装到 | 用途 |
| --- | --- | --- |
| `files/vnc/vnc-desktop.Aptfile` | `/usr/local/share/vnc-desktop.Aptfile` | 桌面包清单（§5） |
| `files/vnc/capture-vnc-user-env.sh` | `/tmp/capture-vnc-user-env` | 记录 VNC 用户名与 `HOME` |
| `files/vnc/install-vnc-desktop-apt-packages.sh` | `/usr/local/bin/install-vnc-desktop-apt-packages` | 按 Aptfile 安装桌面包 |
| `files/vnc/install-google-chrome.sh` | `/usr/local/bin/install-google-chrome` | 添加 Google apt 源并安装 Chrome |
| `files/vnc/configure-google-chrome.sh` | `/usr/local/bin/configure-google-chrome` | Chrome 用户配置与启动参数 |
| `files/vnc/install-locales.sh` | `/usr/local/bin/install-locales` | 生成 `en_US.UTF-8` |
| `files/vnc/install-fonts-and-fontconfig.sh` | `/usr/local/bin/install-fonts-and-fontconfig` | 字体与 fontconfig |
| `files/vnc/install_and_configure_themes.sh` | `/usr/local/bin/install-and-configure-themes` | WhiteSur 主题、图标与光标 |
| `files/vnc/install-remote-vnc-setup.sh` | `/usr/local/bin/install-remote-vnc-setup` | noVNC 1.2.0 与 websockify 0.10.0 |
| `files/vnc/configure_os_display.sh` | `/usr/local/bin/configure-os-display` | XFCE / GTK 显示配置 |
| `files/vnc/install-cursor-artifact-directories.sh` | `/usr/local/bin/install-cursor-artifact-directories` | 创建 artifacts 等目录 |
| `files/vnc/desktop-init.sh` | `/usr/local/share/desktop-init.sh` | Run 时启动桌面（§3） |
| `files/anyos/anyos.conf` | `/usr/local/share/anyos.conf` | 分辨率 1920×1200、96 DPI 与界面字体 |
| `files/anyos/anyos-setup.sh` | `/usr/local/bin/anyos-setup` | 把 `anyos.conf` 套用到桌面配置模板 |

工具包源文件安装后仍保留在 `/opt/cursor/` 中。其余几个目录：

- `artifacts`：安装时由 `install-cursor-artifact-directories` 以 777 权限创建为目录，Run 中被替换为指向 FUSE 的链接（§3）；
- `recording-staging`：录屏暂存目录，由同一步骤创建；
- `logs`：平台日志目录，复核时为空；
- `.exec-daemon/`：`tree` 默认不显示，由 `create-exec-daemon-dir` 以 1777 权限创建，存放 exec-daemon 的请求上下文缓存。

在 `/opt/cursor/` 之外，控制器还留下了 `/home/ubuntu/.cursor/bin/cursor-git-ssh-keygen`（git 的 `gpg.ssh.program`）、`/usr/local/bin/gh` → `/exec-daemon/gh` 和 `/usr/local/bin/cursor-agent-store-fuse`。

---

## 5. 软件包来源

`/usr/local/share/vnc-desktop.Aptfile` 是平台安装桌面包时使用的清单，共 58 个包名，原文见[存档](https://github.com/yuangezhizao/Cursor-Cloud-Agents/blob/db8217941c3f4d017a0ec5098e7603d402aefeb3/usr/local/share/vnc-desktop.Aptfile)。它常被当成"平台装了哪些包"的完整答案，实际上只是环境中 apt 包的来源之一：

| 来源 | 安装的内容 |
| --- | --- |
| 基础镜像 | `ubuntu:24.04`（备选为 luckfox 官方镜像）自带的系统包 |
| 本仓 Dockerfile | SDK 编译依赖、诊断工具、Tailscale |
| 平台资产步骤 | 下载资产前先安装 `curl`、`coreutils` 等基础工具（这几个包也列在 Aptfile 中） |
| 平台 Aptfile 步骤 | 58 个桌面相关包，以及 apt 为它们解析出的依赖 |
| 平台 Chrome 步骤 | 添加 Google apt 源后安装 `google-chrome-stable`，不在 Aptfile 中 |
| 本仓 `install.sh` | `openssh-server` 及其依赖 |

因此，Aptfile 的包名数（58）、某一步的新装数（10-03 的 Aptfile 步骤新装了 406 个）和环境里最终的包总数是三个不同的量。每次 Build 的新装与升级数量还会随软件源变化，不适合作为固定的验收值。exec-daemon、FUSE 组件等由平台直接分发的文件也不经过 dpkg。

两份 Dockerfile 顶部仍保留这 58 个包名的注释清单，方便在镜像定义里直接看到平台会装什么，但它只是记录。Dockerfile 要装哪些包，依据仍是 FROM 镜像的 dpkg（08-30 spec §2.3.1）：不能因为 Aptfile 里已有同名包，就从 Dockerfile 中省略。

---

## 6. 设计决策

### 6.1 平台明细引用存档，本仓只写衔接

| 方案 | 结论 |
| --- | --- |
| A. 新建本规格，平台明细引用 Cursor-Cloud-Agents 固定提交（采用） | 平台步骤与文件产物只维护一份；本仓文档只讲与 Luckfox 配置的衔接 |
| B. 在本规格复制 18 步和 Aptfile 全文 | 否决：与存档重复，平台一变就要改两处 |
| C. 扩写 08-30 spec §2.3 | 否决：该节讲 Dockerfile / `install.sh` / `start.sh` 的分工，不是平台目录 |
| D. 用新数据改写 08-30 plan 的 Build 时间表 | 否决：那是 09-06 一次 Build 的实测记录 |
| E. 扩写 07-13 交付物表 | 否决：07-13 管配置即代码与编译路径 |

引用固定提交而不是分支，链接和 plan 里的核验脚本才会始终指向同一份内容。存档仓库只是文档证据，不是本仓的构建或运行依赖。更新基线时，同时更新引用的提交和 plan 中的证据即可。

### 6.2 09-06 时间表作为历史保留

08-30 plan「Environment Build install 流水」记录的是 2026-09-06 `bld-20260906-a344b2e4-98f2-411d-86fa-d45b6dfa20cb` 那一次的顺序、耗时和磁盘增量（Chrome `152.0.7977.82-1`，Aptfile 步骤新装 408、升级 13）。表格保持原样，只在开头加一句指向本规格。

### 6.3 既有文档的改动

- **指针**：07-13 spec §10、08-30 spec §2.3、08-30 plan 流水引言各加一处指向本规格的链接，不复制命令表。
- **07-13 spec §2.2**：原文说 Dockerfile 模式"由 Cursor 在每次启动时从 Dockerfile 构建镜像"，改为在 Environment Build 时构建、Agent 从快照启动。
- **08-30 spec §2.3**：顺带更正"Chrome 按 Aptfile 安装"的说法。Chrome 由平台的另一个步骤安装。
- **09-14 spec §2.4**：tini 的作用由"再 exec pod-daemon"改为"启动并管理子进程 pod-daemon"。原文读起来像 tini 用 exec 替换了自己，实际上二者是两个进程。
- **`AGENTS.md`**：只改原有的一句，说明桌面包在 Build 时装入快照、Run 时只启动服务。不加本规格的链接：AGENTS.md 是给 Agent 的精简说明，细节留在规格里。
- **两份 Dockerfile**：只改顶部的平台注释。旧注释说桌面包"每次启动"时安装、平台"每次启动 git clean -fd"，都没有依据，现改为区分 Build 与 Run。2026-10-05 在当前活动环境复核了 Aptfile 的哈希和 58 个包名，与注释清单一致，因此更新了复核日期；备选镜像没有重新构建，注释中写明了这一点。FROM dpkg 等其他历史日期不变。

注释改动不影响构建指令，但会改变 Dockerfile 的文件哈希，可能触发 CI 按内容哈希重建镜像。

---

## 7. 已知边界

下列事项没有直接证据，正文不作断言：

- **是否为最新 Build**：没有查询控制台的 active Build。10-03 是已核验的基线，不代表平台之后没有新的 Build。
- **Run 启动顺序**：没有 Run 启动日志。§3 的进程树只反映复核那一刻的状态，看不出启动先后和依赖关系，也无法判断是否为冷启动。
- **`start:core-dumps`**：Build 日志里有这条命令，Run 中没有可以对应的常驻进程。
- **`create-artifacts-dir`**：存档中找不到能归到这一步的写入，无法确定它是否也写过 `/opt/cursor/artifacts`。
- **FUSE 后端**：挂载点和 artifacts 链接存在，不等于后端可读写。2026-10-05 复核时，`/cursor/stores` 下的目录就无法正常列出。
- **备选镜像**：Dockerfile 注释的复核只针对当前活动环境（自建 Ubuntu 24.04），没有重新构建备选的 luckfox 官方镜像。

---

## 8. 常见误读

| 误读 | 实际情况 |
| --- | --- |
| `desktop-init.sh` 负责安装桌面包 | 桌面包在 Build 的 Aptfile 步骤安装；`desktop-init.sh` 只负责启动桌面，Build 和 Run 中都会运行，进程不会进入快照 |
| Aptfile 就是平台安装的全部包 | Aptfile 只列出 58 个直接包名，其他来源见 §5 |
| Build 日志里的 `start:*` 进程会进入快照 | 快照只保存磁盘，进程在 Run 时重新拉起 |
| 平台每次启动都会 `git clean` | 已知的只有 Build 中 `configure-git` 的 `git-cleanup` 子步骤，Run 时是否执行没有证据 |
| `/opt/cursor/artifacts` 是普通目录 | 安装时是目录，Run 中是指向 FUSE 的链接 |
| `/exec-daemon` 由 `create-exec-daemon-dir` 创建 | `/exec-daemon` 来自 `install-exec-daemon`；`create-exec-daemon-dir` 创建的是 `/opt/cursor/.exec-daemon` |
| Aptfile 已有的包，Dockerfile 可以不装 | Dockerfile 只看 FROM 镜像的 dpkg（08-30 spec §2.3.1） |

---

## 9. 验收标准

| 编号 | 通过标准 |
| --- | --- |
| V1 | 本规格状态为已 Review，关联计划存在 |
| V2 | 两份 Dockerfile 去掉注释与空行后和 `dev` 相同；`AGENTS.md` 只改一行且没有新增链接；`environment.json`、`install.sh`、`start.sh` 无改动 |
| V3 | 当前 Aptfile 与存档固定提交中的文件逐字节一致，58 个包名与两份 Dockerfile 注释清单相同 |
| V4 | 10-03 日志中 18 个平台命令的顺序与存档 §4.0.3 一致且全部成功；当前 Agent 的进程关系、挂载、链接与 `/opt/cursor/` 目录树和 §3、§4 一致 |
| V5 | 三处指针有效；08-30 plan 的 09-06 时间表未改；09-14 spec 只改 tini 一行 |

核验脚本和实测结果见关联计划。

---

## 10. QA 记录

本节记录评审中确定的决策。

| ID | 问题 | 结论 | 备注 |
| --- | --- | --- | --- |
| Q1 | 平台安装与启动顺序写在哪里 | 新建本规格，不塞进 07-13 / 08-30 文档 | §6.1 |
| Q2 | Run 部分是否只写 `start.sh` 和 `desktop-init` | 否。写完整命令层：tini / pod-daemon、平台 `start:*`、FUSE 和 `start.sh`；desktop-init 的子进程引用既有规格 | §3 |
| Q3 | 以哪次 Build 为基线 | 2026-10-03 的 Build，运行时部分 2026-10-05 复核；09-06 时间表作为历史保留 | §6.2 |
| Q4 | 平台 18 步和 Aptfile 要不要在本仓再列一遍 | 不列，引用 Cursor-Cloud-Agents 固定提交 | §6.1 |
| Q5 | 是否修改 Dockerfile | 只改顶部平台注释；复核 Aptfile 后更新日期，不动构建指令 | §6.3 |
| Q6 | 是否修改 `AGENTS.md` | 只改原有的一句，不加规格链接 | §6.3 |
| Q7 | 是否编写 plan | 编写；规格评审后再写 | 关联计划 |
