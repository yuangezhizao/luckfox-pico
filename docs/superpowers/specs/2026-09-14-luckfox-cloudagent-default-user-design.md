# Luckfox Pico Cloud Agent 默认运行用户 ubuntu 设计规格（Design Spec）

- **日期**：2026-09-14
- **状态**：待 Review（活动镜像代码已按本规格落地；备选 Dockerfile 的 `USER` 与既有文档指针待对齐）
- **分支**：`cursor/dockerfile-user-ubuntu-1fe9`（起点 `dev`）
- **主题**：把 Cloud Agent 交互会话、工作区属主与桌面栈的默认 Unix 用户从 `root` 改为 `ubuntu`，同时保持 `install` / `start` 所需的 root 能力与既有 OpenSSH / Tailscale 边界
- **关联代码文件**：`.cursor/environment.json`、`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`.cursor/install.sh`、`.cursor/start.sh`、`AGENTS.md`
- **关联规格**：[`2026-07-13-luckfox-cloudagent-env-design.md`](2026-07-13-luckfox-cloudagent-env-design.md)、[`2026-08-30-luckfox-cloudagent-tailscale-design.md`](2026-08-30-luckfox-cloudagent-tailscale-design.md)
- **参考文档**：[Cursor Cloud Agent Setup](https://cursor.com/docs/cloud-agent/setup)、[environment.json schema](https://cursor.com/schemas/environment.schema.json)（`user`：`The user to run the environment as.`）、[Creating a Dockerfile for Cloud Agents](https://cursor.com/environment-json-dockerfile.md)

---

## 1. 概述与目标

既有 Cloud Agent 环境（自建 Ubuntu 24.04 Dockerfile + Tailscale kernel + OpenSSH）里，SSH 登录用户已是 `ubuntu`（`PermitRootLogin no`，NOPASSWD sudo），但 Cursor 跑 `install` / `start` / Agent shell / 工作区 checkout / 平台桌面时默认仍是 **root**。本规格把这些交互面的默认用户改为 **`ubuntu`**（`HOME=/home/ubuntu`；活动镜像 uid 1000）。

达成后：

1. 新 Agent 会话 `whoami` 为 `ubuntu`，`/workspace` 属主为 `ubuntu:ubuntu`，与「编译不要额外 `sudo`」一致。
2. `install.sh` / `start.sh` 仍按 **root 语义** 编写（apt、sysctl、sshd、tailscaled）；提权只发生在 `environment.json` 的 `install` / `start` 包装层。
3. PID 1、`tailscaled`、sshd 监听进程保持 **root**；SSH 登录用户、公钥路径、`PermitRootLogin no` 不变。

**不在本规格范围**：修改 `./build.sh` 或板上固件；把 `tailscaled` / sshd / PID 1 改成非 root；启用 Tailscale SSH；给 `ubuntu` 设登录密码；为镜像增加 `WORKDIR /home/ubuntu`（工作区仍是平台 checkout 的 `/workspace`）；把 Docker 引擎写入本仓 Dockerfile。

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

| 标志 | 作用 |
| --- | --- |
| `-n` | 非交互；`ubuntu` 密码 LOCKED，无 TTY 时绝不能停在密码提示 |
| `-E` | 保留调用方环境。`start.sh` 依赖 `TAILSCALE_AUTHKEY` / `SSH_AUTHORIZED_KEYS`；`install.sh` 把 grilling 写到 `"$HOME/.cursor/skills/grilling/SKILL.md"`，必须保持 `HOME=/home/ubuntu` |

禁止 `sudo -H`（会把 `HOME` 改成 root 的 home）。禁止去掉 `-E`。提权目标为 root（sudo 默认即可），禁止 `-u` 指向非 root。

sudoers 维持既有 `ubuntu ALL=(ALL) NOPASSWD:ALL`（`visudo -cf` 校验的 `/etc/sudoers.d/ubuntu`）。命令列表为 `ALL` 时 sudoers 隐含 `SETENV`，因此 `-E` 合法；不得加 `NOSETENV`，也不得把免密范围缩到无法保留环境的命令。不得从 Cursor 官方 Dockerfile 示例复制 `chpasswd` 或明文用户密码。

缺这层包装、仅靠 `USER ubuntu` 时，Build 的 `install` 以 ubuntu 跑裸 `apt-get update`，失败为 `E: List directory /var/lib/apt/lists/partial is missing`、apt 退出码 100（§7）。

### 2.3 两份 Dockerfile 的落点

活动 `.cursor/Dockerfile` 与备选 `.cursor/Dockerfile.luckfox_pico` 均在 **全部** `RUN`（含 apt、Tailscale、sudoers、`git config --system --add safe.directory '*'`）之后增加：

```dockerfile
# 镜像默认运行用户。须在全部 RUN 之后，否则后续 apt RUN 会以非 root 失败。
USER ubuntu
```

活动 `FROM ubuntu:24.04` 已含 uid 1000 的 `ubuntu`（home `/home/ubuntu`）。备选 FROM 若构建因用户不存在失败，在 `USER` 之前创建 home 为 `/home/ubuntu`、shell 为 `/bin/bash` 的同名账户；不得把 `USER` 或 `useradd` 提前到任何仍需 root 的 apt / Tailscale / sudoers / `git config --system` 的 `RUN` 之前。不设置 `WORKDIR`。

`git config --system` 已对所有用户生效，切换 `USER` 后不必再写 `--global`。

### 2.4 运行时进程身份

| 身份 | 进程 |
| --- | --- |
| `root` | PID 1（`tini`）、`pod-daemon`、`start.sh` 拉起的 `tailscaled`、sshd 监听进程 |
| `ubuntu` | exec-daemon 的 `node`、Agent shell、工作区文件、`desktop-init.sh` 及其 TigerVNC / XFCE / noVNC / websockify、会话 dbus、ssh-agent / gpg-agent |
| `messagebus` | 系统 `dbus-daemon --system` |

OpenSSH 仍只允许 `ubuntu` 公钥登录；`start.sh` 写入 `/home/ubuntu/.ssh/authorized_keys` 的属主与权限不变（见 2026-08-30 §2.4）。`ubuntu` 继续免密 sudo 到 root，供排障与脚本提权，**不**用于日常 `./build.sh`。

---

## 3. 需求

### 3.1 功能需求

| 编号 | 需求 |
| --- | --- |
| F1 | 从含本配置的 draft / active Build 冷启动的 Agent，会话用户为 `ubuntu`，`HOME=/home/ubuntu`。活动镜像 uid 为 1000；备选以用户名与 home 为准，uid 优先与活动镜像对齐为 1000 |
| F2 | `/workspace` 属主为 `ubuntu:ubuntu`；Agent 不以额外 `sudo` 跑 `./build.sh` |
| F3 | `.cursor/environment.json` **不**含 `user` 键；`install` / `start` 分别为 `sudo -n -E bash .cursor/install.sh` 与 `sudo -n -E bash .cursor/start.sh` |
| F4 | 活动与备选 Dockerfile 均以 `USER ubuntu` 结尾，且该指令位于全部 `RUN` 之后 |
| F5 | `install.sh` / `start.sh` 正文不内嵌 `sudo`；Build `install` 退出 0；grilling 落在 `/home/ubuntu/.cursor/skills/grilling/SKILL.md` |
| F6 | 每个 Agent Run 的 `start` 退出 0（`/tmp/cursor/start-user/start-user.status`），sshd 监听 `0.0.0.0:22`，`tailscaled` 仍为 kernel 模式且以 root 运行 |
| F7 | 合入时把 `AGENTS.md`、2026-07-13 spec 中的 `install`/`start` 命令、2026-08-30 spec §2.3 命令字符串与 §3.2「Agent 实际运行用户」改为与本规格一致；不在 `AGENTS.md` 重复端口表 |

### 3.2 非功能需求

| 编号 | 需求 |
| --- | --- |
| N1 | 不引入明文用户密码或 `chpasswd` |
| N2 | 不破坏既有交叉编译与 Tailscale / OpenSSH 目标态（2026-08-30 F1–F8、V1、V5、V8 仍成立） |
| N3 | 身份来源只有镜像 `USER`；Cursor JSON `user` 保持缺省 |

---

## 4. 目标配置与数据流

```text
Environment Build
  Dockerfile USER ubuntu（全部 RUN 之后）
  → 平台以 ubuntu 执行：sudo -n -E bash .cursor/install.sh
       脚本 uid=0，HOME 仍为 /home/ubuntu
       → apt / openssh-server / host key stamp（私有快照）
       → grilling → /home/ubuntu/.cursor/skills/grilling/SKILL.md
  → snapshot

Agent Run
  平台以 ubuntu 执行：sudo -n -E bash .cursor/start.sh
       脚本 uid=0，Secret 与 HOME 保留
       → sysctl / tailscaled(root) / sshd(root)
  Agent shell / 工作区 / 桌面栈 → ubuntu
  Mac：ssh ubuntu@cursor-agent-<suffix> （不变）
```

---

## 5. 验证策略

可复现命令与实测数值见 §7。本节只列通过标准。验收必须使用 snapshot 已含本规格 Dockerfile + `environment.json` 的 draft Build 冷启动；绑在旧 root 快照上的 Agent 不能当作反例。

| 步骤 | 通过标准 |
| --- | --- |
| V1 会话身份 | `whoami` 为 `ubuntu`，`HOME` 为 `/home/ubuntu`；活动镜像另要求 `id -u` 为 `1000` |
| V2 工作区 | `stat -c '%U:%G' /workspace` 为 `ubuntu:ubuntu` |
| V3 JSON | `environment.json` 无 `user` 键；`install`/`start` 字符串与 §2.2 逐字相同 |
| V4 Dockerfile | 活动与备选文件的最后非空指令为 `USER ubuntu`；其前一条相关 `RUN` 仍含 `git config --system` |
| V5 Build / start | 目标 draft Build 为 `SUCCEEDED`；`start-user.status` 为 `0` |
| V6 服务身份 | `sshd` 监听 `0.0.0.0:22`；`tailscaled` 进程用户为 root；Agent 的 bash / exec-daemon `node` 为 ubuntu |
| V7 grilling / sudo | grilling 文件存在于 `/home/ubuntu/.cursor/skills/grilling/SKILL.md`；`sudo -n whoami` 输出 `root` |
| V8 编译回归 | 非交互 `lunch` 后 `./build.sh kernel` 退出码 0（不以 sudo 调用） |

镜像已 `USER ubuntu` 但 JSON 改为裸 `bash .cursor/install.sh` 时，应再次出现 apt 对 `/var/lib/apt/lists/partial` 的权限失败；该路径只用于证明 F5 的必要性，不是合入后的目标态。

---

## 6. 风险与约束

| 风险 | 缓解 |
| --- | --- |
| `USER` 写在 apt `RUN` 之前 | 只允许出现在文件末尾 |
| 无 sudo 包装 | JSON 固定 `sudo -n -E`；缺包装时的失败模式见 §7 |
| `-E` 被 sudoers 拒绝 | 保持 `ALL` 隐含 SETENV；禁止 `NOSETENV` |
| grilling 落到 `/root` | 禁止 `sudo -H` 与去掉 `-E` |
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

缺 sudo 包装（仅 `USER ubuntu` + `bash .cursor/install.sh`）：Build [`bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9) `INSTALL_FAILED`；`apt-get update` 报 `E: List directory /var/lib/apt/lists/partial is missing`，apt 退出码 100。工作区 clone 在失败前已是 `ubuntu:ubuntu`。

仅 JSON `"user": "ubuntu"`、无镜像 `USER`、同样 `sudo -n -E` 包装：Build [`bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9) `SUCCEEDED`；Agent [`bc-558191bf-a55d-5367-a647-a1bcc6e01892`](https://cursor.com/agents/bc-558191bf-a55d-5367-a647-a1bcc6e01892) 的 `whoami` 亦为 `ubuntu`。该路径能满足 F1，但不满足 N3，故不采用。

---

## 8. QA 记录

| ID | 问题 | 用户选择 | 备注 |
| --- | --- | --- | --- |
| Q1 | 默认身份用镜像 `USER` 还是 JSON `user` | ✅ 只用 Dockerfile `USER ubuntu`，省略 JSON `user` | JSON `user` 是 Cursor 专用；两条路径对 `whoami` 等价，见 §7。详见 §2.1 |
| Q2 | `install` / `start` 如何拿到 root | ✅ 只在 `environment.json` 包 `sudo -n -E`；脚本正文保持 root 语义、不内嵌 sudo | `-n` 对 LOCKED 密码；`-E` 保 Secret 与 `HOME`。详见 §2.2 |
| Q3 | 是否 JSON `user` 与 `USER` 双写 | ✅ 否 | 避免双通道。详见 §2.1 |
| Q4 | PID 1 / tailscaled / sshd 是否随会话改成 ubuntu | ✅ 否，保持 root | SSH 登录用户仍为 ubuntu。详见 §2.4 |
| Q5 | 备选 `.cursor/Dockerfile.luckfox_pico` 是否同样 `USER ubuntu` | ✅ 是（由 Q1 推出：身份唯一来源是镜像 `USER`）。全部 `RUN` 之后；FROM 缺账户则先创建 | 否则把 `environment.json` 的 `dockerfile` 指针切到备选会回到 root。详见 §2.3 |

---

## 9. 后续

§8 QA 已闭合。实现步骤、备选镜像 `USER`、既有文档指针与验收命令以用户 Review 本 spec 之后的 implementation plan 为准。
