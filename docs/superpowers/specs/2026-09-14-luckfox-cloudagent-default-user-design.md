# Luckfox Pico Cloud Agent 默认运行用户 ubuntu 设计规格（Design Spec）

- **日期**：2026-09-14
- **状态**：待 Review（活动镜像 `USER ubuntu` + JSON `sudo -n -E` 已落地；grilling 用 `$HOME` + `chown` `$HOME/.cursor/skills`；备选 Dockerfile 同步 `USER ubuntu`）
- **分支**：`cursor/default-ubuntu-user-1fe9`（起点 `dev`，PR #9）
- **主题**：把 Cloud Agent 交互会话、工作区属主与桌面栈的默认 Unix 用户从 `root` 改为 `ubuntu`，同时保持 `install` / `start` 所需的 root 能力与既有 OpenSSH / Tailscale 边界
- **关联代码文件**：`.cursor/environment.json`、`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`.cursor/install.sh`、`.cursor/start.sh`、`AGENTS.md`
- **关联规格**：[`2026-07-13-luckfox-cloudagent-env-design.md`](2026-07-13-luckfox-cloudagent-env-design.md)、[`2026-08-30-luckfox-cloudagent-tailscale-design.md`](2026-08-30-luckfox-cloudagent-tailscale-design.md)
- **参考文档**：[Cursor Cloud Agent Setup](https://cursor.com/docs/cloud-agent/setup)、[environment.json schema](https://cursor.com/schemas/environment.schema.json)（`user`：`The user to run the environment as.`）、[Creating a Dockerfile for Cloud Agents](https://cursor.com/environment-json-dockerfile.md)、Ubuntu 24.04 [`sudo(8)`](https://manpages.ubuntu.com/manpages/noble/man8/sudo.8.html)

---

## 1. 概述与目标

既有 Cloud Agent 环境（自建 Ubuntu 24.04 Dockerfile + Tailscale kernel + OpenSSH）里，SSH 登录用户已是 `ubuntu`（`PermitRootLogin no`，NOPASSWD sudo），但 Cursor 跑 `install` / `start` / Agent shell / 工作区 checkout / 平台桌面时默认仍是 **root**。本规格把这些交互面的默认用户改为 **`ubuntu`**（`HOME=/home/ubuntu`；活动镜像 uid 1000）。

达成后：

1. 新 Agent 会话 `whoami` 为 `ubuntu`，`/workspace` 属主为 `ubuntu:ubuntu`，与「编译不要额外 `sudo`」一致。
2. `install.sh` / `start.sh` 仍按 **root 语义** 编写（apt、sysctl、sshd、tailscaled）；提权只发生在 `environment.json` 的 `install` / `start` 包装层。
3. PID 1、`tailscaled`、sshd 监听进程保持 **root**；SSH 登录用户、公钥路径、`PermitRootLogin no` 不变。
4. grilling 技能文件位于 `$HOME/.cursor/skills/grilling/SKILL.md`。在 `sudo -n -E` 下 `$HOME` 为 `/home/ubuntu`，curl 后 `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`（覆盖 `--create-dirs` 以 root 新建的父目录），ubuntu 可直接读；不把 `/root/.cursor/skills` 改成对其他用户可读。

**不在本规格范围**：修改 `./build.sh` 或板上固件；把 `tailscaled` / sshd / PID 1 改成非 root；启用 Tailscale SSH；给 `ubuntu` 设登录密码；为镜像增加 `WORKDIR /home/ubuntu`（工作区仍是平台 checkout 的 `/workspace`）；把 Docker 引擎写入本仓 Dockerfile；把 `/root` 或 `/root/.cursor/skills` 放开给 ubuntu。

本规格覆盖活动镜像（`.cursor/Dockerfile`）与备选镜像（`.cursor/Dockerfile.luckfox_pico`）。合入时同步改 `AGENTS.md` 与既有 spec 中仍写「Agent 以 root 运行」或 `install`/`start` 为裸 `bash .cursor/*.sh` 的句子；不以本文件重复 Tailscale / OpenSSH 细节。

---

## 2. 设计决策

### 2.1 两套身份开关，只采用镜像 `USER`

| 开关 | 作用域 | 本设计 |
| --- | --- | --- |
| Dockerfile 末尾 `USER ubuntu` | 镜像默认 Linux 用户；离开 Cursor 后仍生效 | **采用**。必须写在全部 `RUN` 之后，否则后续 apt `RUN` 会以非 root 失败 |
| `environment.json` 的 `"user": "ubuntu"` | 仅 Cursor 运行时（install / start / Agent shell / 工作区属主 / VNC） | **省略**。该字段必须对镜像内已存在的用户取值；与 `USER` 同时写会形成双通道 |

Cursor 文档把 Dockerfile `USER ubuntu`（及可选的 `WORKDIR /home/ubuntu`）标为良好实践；schema 另提供可选 `user`。两条路径都能把会话用户变成 `ubuntu`（§7）。本仓 `.cursor/Dockerfile*` 虽为 Cloud Agent 专用，仍以镜像 `USER` 为唯一来源，避免身份只写在 Cursor JSON 里。

禁止同时声明 JSON `user` 与镜像 `USER` 来「双保险」：以后改其中一个会让另一条通道静默覆盖，排障时无法判断到底是谁决定了身份。

### 2.2 `install` / `start` 只在 JSON 层提权

`.cursor/install.sh` 与 `.cursor/start.sh` 继续假设自己是 root：写 `/var/lib/apt`、`/etc/sysctl.d`、`/etc/ssh`、`/run/sshd`，启动 `tailscaled` 与 sshd。不在脚本内部再包 `sudo`。

`environment.json` 目标态（**无** `user` 键）：

```json
{
  "build": {
    "dockerfile": "Dockerfile",
    "context": ".."
  },
  "install": "sudo -n -E bash .cursor/install.sh",
  "start": "sudo -n -E bash .cursor/start.sh"
}
```

`sudo` 默认把后续命令换成 **root** 执行（等价于未写的 `-u root`）。`ubuntu ALL=(ALL) NOPASSWD:ALL` 使提权无需密码。

| 标志 | 含义（Ubuntu 24.04 `sudo(8)`） | 本仓为什么要 |
| --- | --- | --- |
| `-n` / `--non-interactive` | 不向用户要任何输入；若策略本该要密码则直接失败，不挂起等 TTY | Cloud Agent 的 install/start 没有人看着密码提示。`ubuntu` 密码 LOCKED；若 sudoers 没 NOPASSWD，普通 `sudo` 会一直等密码，Build 卡死。`-n` 让配置错误立刻失败 |
| `-E` / `--preserve-env` | 请求保留调用者环境。默认 sudoers 有 `Defaults env_reset`，会丢掉大部分环境、换成 root 的最小集合 | `start.sh` 开头用 `${TAILSCALE_AUTHKEY:?}` / `${SSH_AUTHORIZED_KEYS:?}`；还需要 `CURSOR_CONVERSATION_ID` 等平台变量。没有 `-E`，`start.sh` 会在「Secret 不存在」处非零退出 |

禁止 `sudo -H`（把 `HOME` 改成 root 的 home）。禁止去掉 `-E`。提权目标为 root（sudo 默认即可），禁止 `-u` 指向非 root。

sudoers 维持既有 `ubuntu ALL=(ALL) NOPASSWD:ALL`（`visudo -cf` 校验的 `/etc/sudoers.d/ubuntu`）。命令列表为 `ALL` 时 sudoers 隐含 `SETENV`，因此 `-E` 合法；缺 SETENV 时 `sudo -E` 会报 `sorry, you are not allowed to preserve the environment`。不得加 `NOSETENV`，也不得把免密范围缩到无法保留环境的命令。不得从 Cursor 官方 Dockerfile 示例复制 `chpasswd` 或明文用户密码。

更窄的写法 `sudo -n --preserve-env=TAILSCALE_AUTHKEY,SSH_AUTHORIZED_KEYS,CURSOR_CONVERSATION_ID` 能少把 `LD_PRELOAD` 之类带进 root，但会漏掉未列入的平台注入变量。本设计采用裸 `-E`。grilling 的 `$HOME` 也靠 `-E` 保持为 `/home/ubuntu`（§2.6）；禁止 `sudo -H`。

缺这层包装、仅靠 `USER ubuntu` 时，Build 的 `install` 以 ubuntu 跑裸 `apt-get update`，失败为 `E: List directory /var/lib/apt/lists/partial is missing`、apt 退出码 100（§7）。

### 2.3 两份 Dockerfile 的落点

活动 `.cursor/Dockerfile` 与备选 `.cursor/Dockerfile.luckfox_pico` 均在 **全部** `RUN`（含 apt、Tailscale、sudoers、`git config --system --add safe.directory '*'`）之后声明 `USER ubuntu`。备选 FROM 若无 `ubuntu` 账户，在 `USER` 之前 `id -u ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ubuntu`。不得把 `USER` 或 `useradd` 提前到任何仍需 root 的 apt / Tailscale / sudoers / `git config --system` 的 `RUN` 之前。不设置 `WORKDIR`。

`git config --system` 已对所有用户生效，切换 `USER` 后不必再写 `--global`。

### 2.4 运行时进程身份

平台基础设施保持 root；Agent 终端、exec-daemon、桌面/VNC 为 ubuntu。`start.sh` 经 `sudo -n -E` 升到 root 后，`tailscaled` 与 sshd 一直以 root 跑。PID 1 永远是 root 的 `tini`，与 JSON `user` / Dockerfile `USER` 无关。

**root（uid 0）常驻**

| 进程 | 作用 | 谁拉起 |
| --- | --- | --- |
| `tini`（PID 1） | 容器 init，再 exec pod-daemon | 平台 |
| `pod-daemon` | Pod 控制面（SSH auth sock、API sock） | tini |
| `tailscaled` | Tailscale kernel 模式（1054 HTTP / 1055 SOCKS5） | `start.sh`（sudo 后的 root） |
| `sshd` | OpenSSH 监听 `:22`（无已登录会话时没有 priv/net 子进程） | 同上 |

**ubuntu（uid 1000）— Agent 与桌面**

| 进程 | 作用 |
| --- | --- |
| `node`（exec-daemon） | 终端/PTY、命令执行（父进程是 pod-daemon） |
| `cursor-agent-store-fuse` | 挂载 `/cursor/stores` 技能与状态 |
| 交互 `bash` | IDE 终端、Agent 下发的命令 |
| `desktop-init.sh` | 平台桌面初始化 |
| `tigervncserver` / `Xtigervnc` | VNC `:1`，端口 5901 |
| `xfce4-session`、`xfwm4`、`xfsettingsd`、`xfce4-panel`、`xfdesktop`、`xfconfd` | XFCE |
| Thunar、plank | 文件管理器、dock |
| bash + python3 websockify | noVNC，端口 26058 |
| `dbus-launch` / session `dbus-daemon` | 会话总线 |
| `at-spi-bus-launcher` / `at-spi2-registryd` | 无障碍 |
| `ssh-agent`、`gpg-agent` | 会话密钥代理 |
| `bamfdaemon`、`dconf-service` | 窗口匹配、桌面配置 |
| `tail -f /dev/null` | desktop-init 保活 |

**其它用户**

| 用户 | uid | 进程 |
| --- | --- | --- |
| `messagebus` | 101 | 系统 `dbus-daemon --system`（不是 ubuntu 的 session dbus） |

无 `nobody` 常驻进程，也无已建立的 ssh 登录子进程（除非 Mac 已连上）。

OpenSSH 仍只允许 `ubuntu` 公钥登录；`start.sh` 写入 `/home/ubuntu/.ssh/authorized_keys` 的属主与权限不变（见 2026-08-30 §2.4）。`ubuntu` 继续免密 sudo 到 root，供排障与脚本提权，**不**用于日常 `./build.sh`。

### 2.5 Unix 账号盘点

活动 `ubuntu:24.04` 镜像 + install 装包后 `/etc/passwd` 共 **25** 个账号。真正能当交互用户的只有 **root** 与 **ubuntu**。没有其他 UID≥1000 的普通用户（没有 `node`、`cursor` 等额外账号）。`w` / `who` 在 Cloud Agent 上显示 0 user（无 tty 登录），不能用来判断默认身份。

| 用户 | UID | 家目录 | Shell | 用途 |
| --- | --- | --- | --- | --- |
| `root` | 0 | `/root` | `/bin/bash` | PID 1、pod-daemon、`start.sh` 拉起的 tailscaled/sshd |
| `ubuntu` | 1000 | `/home/ubuntu` | `/bin/bash` | 基础镜像预置；本规格下的 Agent / 工作区 / 桌面；SSH 登录入口（`PermitRootLogin no`）；附加组 `adm, dialout, cdrom, floppy, sudo, audio, dip, video, plugdev`；NOPASSWD sudo |
| `sync` | 4 | `/bin` | `/bin/sync` | Debian/Ubuntu 传统账号，不是交互用户 |

其余账号 shell 均为 `/usr/sbin/nologin`，不是给 Agent 用的：

| UID | 用户 | 来源 |
| --- | --- | --- |
| 1–13 | `daemon`, `bin`, `sys`, `games`, `man`, `lp`, `mail`, `news`, `uucp`, `proxy` | Ubuntu 基础系统 |
| 33–39 | `www-data`, `backup`, `list`, `irc` | 同上 |
| 42 | `_apt` | apt |
| 100 | `tcpdump` | 本 Dockerfile 安装了 `tcpdump` |
| 101 | `messagebus` | D-Bus（平台桌面初始化） |
| 102 | `sshd` | `install.sh` 安装的 OpenSSH |
| 996–998 | `systemd-resolve` / `timesync` / `network` | systemd |
| 65534 | `nobody` | 无特权占位 |

改 `USER` 之前，Agent 会话与工作区属主是 root；改完之后是 ubuntu。passwd 账号集合不变。

### 2.6 grilling 技能路径

`.cursor/install.sh` 把 grilling 写到磁盘，供 Agent 当全局技能用（2026-07-13）。Cloud Agent 用户级扫描路径是运行用户的 `~/.cursor/skills/`。

`$HOME` 只影响那一行 `curl`。`apt-get` 不看 `$HOME`，包仍进系统目录。脚本在 sudo 下 euid=0；`$HOME` 跟标志有关。sudoers 默认 `Defaults env_reset`：不加 `-E` 会丢掉调用方环境，`HOME` 变成目标用户 root 的 `/root`。加了 `-E` 才保住 ubuntu 的 `HOME=/home/ubuntu`。`-H` 会覆盖为 root 的 home。本机以 ubuntu 调 sudo 实测：

| 命令 | 脚本里的 `$HOME` | 文件属主 |
| --- | --- | --- |
| `sudo -n bash .cursor/install.sh`（无 `-E`） | `/root` | root |
| `sudo -n -E bash .cursor/install.sh`（当前 JSON） | `/home/ubuntu` | 仍是 root（root 在写） |
| `sudo -n -H ...` 或 `sudo -n -E -H ...` | `/root`（`-H` 覆盖） | root |

因此不写死路径、只用 `$HOME/.cursor/skills/grilling/SKILL.md`。在现在的 `sudo -n -E` 下，会装到 `/home/ubuntu/.cursor/skills/grilling/`，这是官方用户级扫描路径。这和「装到 `/root`」不是一回事：`/root/.cursor/skills` 为 `750 root:root` 时 ubuntu 读不了，是因为当时 `$HOME=/root`（无 `-E`，或 install 本身以 root 跑）。本 VM（Run [`bc-8b3d43cb-d3cb-4a47-abec-60f947961fe9`](https://cursor.com/agents/bc-8b3d43cb-d3cb-4a47-abec-60f947961fe9)）实测 `su -s /bin/bash ubuntu -c 'cat /root/.cursor/skills/grilling/SKILL.md'` 为 `Permission denied`。把 `/root` 改成 o+rx 不采用。

硬编码 `/home/ubuntu/...` + `install -d -o ubuntu` + `chown` 能防有人去掉 `-E` 或加上 `-H`，以及路径对了但属主仍是 root。本设计保持 `sudo -n -E`、禁止 `sudo -H`，不采用硬编码。chown 仍要留：路径对了，属主仍是 root。官方扫描只要求路径在 `~/.cursor/skills/`；ubuntu 读 `644` + 父目录可 traverse 通常可以，属主仍用 ubuntu 更干净。

`curl --create-dirs` 以 root 把尚不存在的父目录建成 `750 root:root`（典型 umask 027）。ubuntu 无法 traverse 该父目录，故 chown 目标是 `$HOME/.cursor/skills`（覆盖 curl 新建的 `skills` 及其下 grilling）。属主改为 ubuntu 后 `750` 即可进入，不必再 chmod。当前快照 `/home/ubuntu/.cursor` 已是 `ubuntu:ubuntu` `755`，curl 只新建 `skills`。若连 `.cursor` 也不存在，它同样会被建成 `750 root:root`，那时 chown 需提到 `$HOME/.cursor`。

```bash
curl ... --create-dirs --output "$HOME/.cursor/skills/grilling/SKILL.md" "..."
chown -R ubuntu:ubuntu "$HOME/.cursor/skills"
```

`/cursor/stores/user/skills/grilling/SKILL.md` 是 Cursor 用户技能仓库（fuse），不是 `install.sh` 的交付物，不能替代 Build 快照里的环境 grilling。平台注入的其它技能（plugins、`skills-cursor`）由 Cursor 按运行用户安置。

---

## 3. 需求

### 3.1 功能需求

| 编号 | 需求 |
| --- | --- |
| F1 | 从含本配置的 draft / active Build 冷启动的 Agent，会话用户为 `ubuntu`，`HOME=/home/ubuntu`。活动镜像 uid 为 1000；备选以用户名与 home 为准，uid 优先与活动镜像对齐为 1000 |
| F2 | `/workspace` 属主为 `ubuntu:ubuntu`；Agent 不以额外 `sudo` 跑 `./build.sh` |
| F3 | `.cursor/environment.json` **不**含 `user` 键；`install` / `start` 分别为 `sudo -n -E bash .cursor/install.sh` 与 `sudo -n -E bash .cursor/start.sh` |
| F4 | 活动与备选 Dockerfile 均以 `USER ubuntu` 结尾，且该指令位于全部 `RUN` 之后；备选 FROM 无账户时先 `useradd` |
| F5 | `install.sh` / `start.sh` 正文不内嵌 `sudo`；Build `install` 退出 0；grilling 落在 `/home/ubuntu/.cursor/skills/grilling/SKILL.md`；`$HOME/.cursor/skills` 与该文件属主均为 `ubuntu:ubuntu`，ubuntu 无需 sudo 即可 traverse 并读 |
| F6 | 每个 Agent Run 的 `start` 退出 0（`/tmp/cursor/start-user/start-user.status`），sshd 监听 `0.0.0.0:22`，`tailscaled` 仍为 kernel 模式且以 root 运行 |
| F7 | 合入时把 `AGENTS.md`、2026-07-13 spec 中的 `install`/`start` 命令、2026-08-30 spec §2.3 命令字符串与 §3.2「Agent 实际运行用户」改为与本规格一致；不在 `AGENTS.md` 重复端口表 |

### 3.2 非功能需求

| 编号 | 需求 |
| --- | --- |
| N1 | 不引入明文用户密码或 `chpasswd` |
| N2 | 不破坏既有交叉编译与 Tailscale / OpenSSH 目标态（2026-08-30 F1–F8、V1、V5、V8 仍成立） |
| N3 | 身份来源只有镜像 `USER`；Cursor JSON `user` 保持缺省 |
| N4 | 不把 `/root` 或 `/root/.cursor/skills` 改为其他用户可读 |

---

## 4. 目标配置与数据流

```text
Environment Build
  Dockerfile USER ubuntu（全部 RUN 之后）
  → 平台以 ubuntu 执行：sudo -n -E bash .cursor/install.sh
       脚本 uid=0
       → grilling → /home/ubuntu/.cursor/skills/（ubuntu:ubuntu，含 grilling/SKILL.md）
       → apt / openssh-server / host key stamp（私有快照）
  → snapshot

Agent Run
  平台以 ubuntu 执行：sudo -n -E bash .cursor/start.sh
       脚本 uid=0，Secret 与平台环境保留
       → sysctl / tailscaled(root) / sshd(root)
  Agent shell / 工作区 / 桌面栈 → ubuntu
  Mac：ssh ubuntu@cursor-agent-<suffix> （不变）
```

---

## 5. 验证策略

可复现命令与实测数值见 §7。本节只列通过标准。验收必须使用 snapshot 已含本规格 Dockerfile + `environment.json` + `install.sh` 的 draft Build 冷启动；绑在旧 root 快照上的 Agent 不能当作反例。

| 步骤 | 通过标准 |
| --- | --- |
| V1 会话身份 | `whoami` 为 `ubuntu`，`HOME` 为 `/home/ubuntu`；活动镜像另要求 `id -u` 为 `1000` |
| V2 工作区 | `stat -c '%U:%G' /workspace` 为 `ubuntu:ubuntu` |
| V3 JSON | `environment.json` 无 `user` 键；`install`/`start` 字符串与 §2.2 逐字相同 |
| V4 Dockerfile | 活动与备选文件的最后非空指令为 `USER ubuntu`；备选在 `USER` 前有 `useradd` 回退 |
| V5 Build / start | 目标 draft Build 为 `SUCCEEDED`；`start-user.status` 为 `0` |
| V6 服务身份 | `sshd` 监听 `0.0.0.0:22`；`tailscaled` 进程用户为 root；Agent 的 bash / exec-daemon `node` 为 ubuntu |
| V7 grilling / sudo | `stat -c '%U:%G' /home/ubuntu/.cursor/skills` 与 `.../grilling/SKILL.md` 均为 `ubuntu:ubuntu`；ubuntu 无 sudo 可读该文件；`sudo -n whoami` 输出 `root`；`/root/.cursor/skills/grilling` 不存在 |
| V8 编译回归 | 非交互 `lunch` 后 `./build.sh kernel` 退出码 0（不以 sudo 调用） |

镜像已 `USER ubuntu` 但 JSON 改为裸 `bash .cursor/install.sh` 时，应再次出现 apt 对 `/var/lib/apt/lists/partial` 的权限失败；该路径只用于证明 F5 对 apt 的必要性，不是合入后的目标态。

---

## 6. 风险与约束

| 风险 | 缓解 |
| --- | --- |
| `USER` 写在 apt `RUN` 之前 | 只允许出现在文件末尾 |
| 无 sudo 包装 | JSON 固定 `sudo -n -E`；缺包装时的失败模式见 §7 |
| `-E` 被 sudoers 拒绝 | 保持 `ALL` 隐含 SETENV；禁止 `NOSETENV` |
| grilling 落到 `/root`，或落在 `/home/ubuntu` 但父目录 `750 root:root` | JSON 保持 `sudo -n -E`（禁止 `-H`）；curl 后 `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`；不 chmod `/root` |
| 备选 FROM 无 `ubuntu` 账户 | §2.3：`USER` 前按需 `useradd` |
| 旧 Build 仍是 root | 功能分支 Agent 复用 default branch 的 active Build；本变更验收必须 `refs` 指向本分支的 draft Build |
| 官方示例 `chpasswd` | 不采用；SSH 仅公钥，`ubuntu` 密码保持 LOCKED |

---

## 7. 验证证据

活动镜像目标态（Dockerfile 末尾 `USER ubuntu`，JSON 无 `user`，`install`/`start` 为 `sudo -n -E bash .cursor/*.sh`）：

| 项 | 值 |
| --- | --- |
| Environment Build | [`bld-20260912-2957aa34-5211-416a-bf60-30089760fa3c`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260912-2957aa34-5211-416a-bf60-30089760fa3c) `SUCCEEDED` |
| 冷启动 Agent | [`bc-537e4468-e6c3-595d-bfec-33118939c710`](https://cursor.com/agents/bc-537e4468-e6c3-595d-bfec-33118939c710) |
| `whoami` / `id -u` / `HOME` | `ubuntu` / `1000` / `/home/ubuntu` |
| `stat -c '%U:%G' /workspace` | `ubuntu:ubuntu` |
| `start-user.status` | `0` |
| sshd | `0.0.0.0:22` 监听 |
| JSON `user` | 缺省（文件中无该键） |
| 进程分工 | 与 §2.4 一致：root 为 tini / pod-daemon / tailscaled / sshd；ubuntu 为 exec-daemon `node`、Agent bash、desktop-init 与 VNC/XFCE；`messagebus` 跑系统 dbus |

缺 sudo 包装（仅 `USER ubuntu` + `bash .cursor/install.sh`）：Build [`bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9) `INSTALL_FAILED`；`apt-get update` 报 `E: List directory /var/lib/apt/lists/partial is missing`，apt 退出码 100。工作区 clone 在失败前已是 `ubuntu:ubuntu`。

仅 JSON `"user": "ubuntu"`、无镜像 `USER`、同样 `sudo -n -E` 包装：Build [`bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9) `SUCCEEDED`；Agent [`bc-558191bf-a55d-5367-a647-a1bcc6e01892`](https://cursor.com/agents/bc-558191bf-a55d-5367-a647-a1bcc6e01892) 的 `whoami` 亦为 `ubuntu`。该路径能满足 F1，但不满足 N3，故不采用。

grilling 权限（root 身份 Build 的遗留路径，Run [`bc-8b3d43cb-d3cb-4a47-abec-60f947961fe9`](https://cursor.com/agents/bc-8b3d43cb-d3cb-4a47-abec-60f947961fe9)）：

| 命令 | 结果 |
| --- | --- |
| `getent passwd \| wc -l` | `25` |
| `stat -c '%a %U:%G' /root/.cursor/skills` | `750 root:root` |
| `su -s /bin/bash ubuntu -c 'cat /root/.cursor/skills/grilling/SKILL.md'` | `Permission denied` |
| `su -s /bin/bash ubuntu -c 'head -1 /cursor/stores/user/skills/grilling/SKILL.md'` | 可读（fuse 用户仓库，不是 install 交付物） |

本机以 ubuntu 调 `sudo -n` / `-E` / `-H` 实测 `$HOME`，数值见 §2.6。

`$HOME` 落盘、仅 chown `grilling` 子目录（Build [`bld-20260914-fe2cfdda-7915-4992-b21d-77668da58439`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260914-fe2cfdda-7915-4992-b21d-77668da58439) / Agent [`bc-d81aa084-2998-5c6f-ab15-b764afe60840`](https://cursor.com/agents/bc-d81aa084-2998-5c6f-ab15-b764afe60840)）：

| 项 | 值 |
| --- | --- |
| `whoami` / `id -u` / `HOME` | `ubuntu` / `1000` / `/home/ubuntu` |
| `start-user.status` | `0` |
| `/root/.cursor/skills/grilling` | 不存在 |
| `stat -c '%a %U:%G' /home/ubuntu/.cursor` | `755 ubuntu:ubuntu` |
| `stat -c '%a %U:%G' /home/ubuntu/.cursor/skills` | `750 root:root` |
| ubuntu 无 sudo 读 `/home/ubuntu/.cursor/skills/grilling/SKILL.md` | `Permission denied`（无法 traverse 父目录） |

`$HOME` 落盘且 `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`（Build [`bld-20260914-5e24bf83-5724-4420-9878-374d5bd73267`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260914-5e24bf83-5724-4420-9878-374d5bd73267) `SUCCEEDED` / Agent [`bc-f468642b-cdda-5775-bfd6-889a44b60f7f`](https://cursor.com/agents/bc-f468642b-cdda-5775-bfd6-889a44b60f7f)）：

| 项 | 值 |
| --- | --- |
| `whoami` / `id -u` / `HOME` | `ubuntu` / `1000` / `/home/ubuntu` |
| `start-user.status` | `0` |
| JSON `user` | 缺省；`install`/`start` 为 `sudo -n -E bash .cursor/*.sh` |
| `/root/.cursor/skills/grilling` | 不存在 |
| `stat -c '%a %U:%G' /home/ubuntu/.cursor` | `755 ubuntu:ubuntu` |
| `stat -c '%a %U:%G' /home/ubuntu/.cursor/skills` | `750 ubuntu:ubuntu` |
| `stat -c '%a %U:%G' /home/ubuntu/.cursor/skills/grilling` | `750 ubuntu:ubuntu` |
| `stat -c '%a %U:%G' .../grilling/SKILL.md` | `644 ubuntu:ubuntu` |
| ubuntu 无 sudo `head` 该文件 | 退出码 0，文件含 `name: grilling` |
| `sudo -n whoami` | `root` |

---

## 8. QA 记录

| ID | 问题 | 用户选择 | 备注 |
| --- | --- | --- | --- |
| Q1 | 默认身份用镜像 `USER` 还是 JSON `user` | ✅ 只用 Dockerfile `USER ubuntu`，省略 JSON `user` | JSON `user` 是 Cursor 专用；两条路径对 `whoami` 等价，见 §7。详见 §2.1 |
| Q2 | `install` / `start` 如何拿到 root | ✅ 只在 `environment.json` 包 `sudo -n -E`；脚本正文保持 root 语义、不内嵌 sudo | `-n` 非交互；`-E` 保 Secret 与平台变量；不用 `--preserve-env=list`。详见 §2.2 |
| Q3 | 是否 JSON `user` 与 `USER` 双写 | ✅ 否 | 避免双通道。详见 §2.1 |
| Q4 | PID 1 / tailscaled / sshd 是否随会话改成 ubuntu | ✅ 否，保持 root | SSH 登录用户仍为 ubuntu。详见 §2.4 |
| Q5 | 备选 `.cursor/Dockerfile.luckfox_pico` 是否同样 `USER ubuntu` | ✅ 是（由 Q1 推出）。全部 `RUN` 之后；FROM 缺账户则先创建 | 否则把 `dockerfile` 指针切到备选会回到 root。详见 §2.3 |
| Q6 | ubuntu 能否读 `/root/.cursor/skills` 下的 grilling；如何保证技能可用 | ✅ 不能读（`750`）。不写死路径，用 `$HOME/.cursor/skills/grilling`（`sudo -n -E` 下即为 `/home/ubuntu/...`），再 `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`。禁止 `-H`，不 chmod `/root` | fuse 用户仓库可读但不能替代 install 产物。仅 chown `grilling` 时父目录仍为 `750 root:root`，ubuntu 无法 traverse（§7）。硬编码 `install -d -o ubuntu` 不采用。详见 §2.6 |
| Q7 | 是否安装 `tree` | ❌ 暂不安装 | 排查 CLI 维持既有 `htop`/`neofetch` |

---

## 9. 后续

§8 QA 已闭合。实现步骤、既有文档指针（F7）与新 draft Build 验收以用户 Review 本 spec 之后的 implementation plan 为准。
