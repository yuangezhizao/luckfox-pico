# Luckfox Pico Cloud Agent 默认运行用户 ubuntu 实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Cloud Agent 交互会话、工作区属主与桌面栈的默认 Unix 用户从 `root` 改为 `ubuntu`，同时保持 `install` / `start` 的 root 能力与既有 OpenSSH / Tailscale 边界。

**Architecture:** 身份只来自两条 Dockerfile 末尾的 `USER ubuntu`（备选官方 FROM 无账户时先 `id -u ubuntu || useradd`）。`.cursor/environment.json` 不声明 `user`；`install` / `start` 为 `sudo -n -E bash .cursor/*.sh`。脚本正文保持 root 语义。grilling 写到 `$HOME/.cursor/skills/` 后 `chown -R ubuntu:ubuntu`。PID 1 / `tailscaled` / sshd 仍为 root。

**Tech Stack:** Cursor Cloud Agent Dockerfile / `environment.json`、Ubuntu 24.04（活动）与 Luckfox 官方 22.04 容器镜像（备选）、Bash、sudo NOPASSWD、既有 OpenSSH 与 Tailscale kernel。

**Spec:** [`docs/superpowers/specs/2026-09-14-luckfox-cloudagent-default-user-design.md`](../specs/2026-09-14-luckfox-cloudagent-default-user-design.md)

## Global Constraints

- 使用现有分支 `cursor/default-ubuntu-user-1fe9`，PR #9 base 为 `dev`；直接使用当前工作树，不创建 worktree。
- 本 PR 相对 `origin/dev` 恰好两个提交：实现（`.cursor/*`）在前，superpowers 文档在最后。改实现合进第一个提交并保留其 AuthorDate `2026-09-11 01:30:34 +0800`；改文档 amend 最后一个提交并保留其 AuthorDate。作者使用 Cursor Agent。
- 仅修改 `.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`.cursor/environment.json`、`.cursor/install.sh`、`AGENTS.md`、本 plan、2026-09-14 spec、2026-07-13 spec 中已对齐的 `install` 指针，以及 2026-08-30 spec §2.3 命令字符串、§3.2 用户表与 Q8 中同一组 `install`/`start` 字符串。不改 `./build.sh`、板上固件、`.cursor/start.sh` 正文、08-30 plan、Tailscale policy/ACL。
- 禁止 JSON `"user"`；禁止 `sudo -H`；禁止去掉 `-E`；禁止 `chpasswd` / 明文用户密码；禁止 chmod `/root`；禁止硬编码 `/home/ubuntu` 作为 grilling 路径。
- 备选 Dockerfile 保留 `id -u ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ubuntu`，不锁 `-u 1000`。`USER` 必须在 docker build 的全部 `RUN` 之后；JSON 的 `sudo -n -E` 不覆盖构建期 `RUN`。
- Cursor Secrets 不得进入 git、日志、plan 或提交信息。
- 对本分支镜像 / `install` 的验收必须用 `refs` 指向 `cursor/default-ubuntu-user-1fe9` 的 draft Build；绑在旧 root 快照上的 Agent 不能当反例。
- 执行 plan 时只允许在「最终验证证据」和「与计划的偏离及原因」中回填可复现命令与实测值。Spec 只保留通过标准；Build ID 与实测表只写本 plan。已完成 Task 只保留步骤与文件目录。`git cz` 主题为 `type(scope): <gitmoji> subject`；body 用 `- ` 并列 why，末尾只留一个 `详见 spec §X` 指针。
- 所有多命令验证块以 `set -euo pipefail` 开头。

---

## File Structure

| 文件 | 责任 |
| --- | --- |
| `.cursor/Dockerfile` | 全部 `RUN` 之后 `USER ubuntu`；构建期 apt/Tailscale/sudoers 仍为 root |
| `.cursor/Dockerfile.luckfox_pico` | 同上，且 `USER` 前 `id \|\| useradd` |
| `.cursor/environment.json` | 无 `user` 键；`install`/`start` 为 `sudo -n -E bash .cursor/*.sh` |
| `.cursor/install.sh` | 仍按 root 语义；grilling 用 `$HOME` + `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"` |
| `AGENTS.md` | 会话用户 `ubuntu`；不抄 `install`/`start`、不链 spec、不重复端口表 |
| `docs/superpowers/specs/2026-09-14-luckfox-cloudagent-default-user-design.md` | 设计规格（目标态、需求、通过标准）；实测数值在本 plan「最终验证证据」 |
| `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` | `install` 指针已对齐 `sudo -n -E`（本 PR 文档提交已含） |
| `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` | §2.3 / §3.2 / Q8 的运行用户与 `install`/`start` 字符串 |
| `docs/superpowers/plans/2026-09-14-luckfox-cloudagent-default-user.md` | 本文件：Task、完成情况、最终验证证据 |

### Task 1: 运行时配置（已完成）

**落地文件（以仓库为准，不在此重复脚本正文）：**

- Modify: `.cursor/Dockerfile`（末尾 `USER ubuntu`）
- Modify: `.cursor/Dockerfile.luckfox_pico`（`id \|\| useradd` 后 `USER ubuntu`）
- Modify: `.cursor/environment.json`（无 `user`；`sudo -n -E bash .cursor/install.sh` / `sudo -n -E bash .cursor/start.sh`）
- Modify: `.cursor/install.sh`（`$HOME/.cursor/skills/grilling/SKILL.md` + `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`）

**Interfaces:** 消费 Cursor `install`/`start` 与 Secrets；产出会话用户 `ubuntu`、`HOME=/home/ubuntu`。命令形态见 Spec §2.2–§2.6。

- [x] **Step 1:** 活动 Dockerfile `USER ubuntu`
- [x] **Step 2:** 备选 Dockerfile `useradd` 回退 + `USER ubuntu`
- [x] **Step 3:** JSON `sudo -n -E`，省略 `user`
- [x] **Step 4:** grilling `$HOME` + 对 `$HOME/.cursor/skills` 做 `chown`
- [x] **Step 5:** 实现提交（AuthorDate `2026-09-11 01:30:34 +0800`）

### Task 2: F7 文档指针（已完成）

**Files:**

- Modify: `AGENTS.md:17`
- Modify: `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`（§2.3 两处命令字符串、§3.2 用户表、Q8 中同一组字符串）

2026-07-13 spec 的 `install` 字符串已是 `sudo -n -E bash .cursor/install.sh`，不要再改。不在 `AGENTS.md` 写端口表、不抄 `install`/`start` 命令、不链 spec。

**Interfaces:** 消费 Spec F7 / §2.2 / §2.4；不改运行时脚本。

- [x] **Step 1: 改 `AGENTS.md` 入口句**

把 Cloud Agent 环境那一条里的：

```text
`install` / `start` 字段只调用 `bash .cursor/install.sh` 与 `bash .cursor/start.sh`。
```

换成：

```text
默认会话用户为 `ubuntu`（`HOME=/home/ubuntu`）；编译不要额外 `sudo`。
```

不把 `environment.json` 的 `install`/`start` 抄进 `AGENTS.md`，不链 09-14 spec。

- [x] **Step 2: 改 08-30 spec §2.3 命令字符串**

将 `.cursor/install.sh` 行首的 `` `environment.json.install` 为 `bash .cursor/install.sh` `` 换成 `` `environment.json.install` 为 `sudo -n -E bash .cursor/install.sh` ``。将 `.cursor/start.sh` 行首的 `` `environment.json.start` 为 `bash .cursor/start.sh` `` 换成 `` `environment.json.start` 为 `sudo -n -E bash .cursor/start.sh` ``。其余 OpenSSH / Tailscale 正文不动。

- [x] **Step 3: 改 08-30 spec §3.2 用户表**

将 `root` 行说明从 `Agent 实际运行用户（PID 1、编译、Tailscale 等）` 换成 `PID 1、pod-daemon、start.sh 拉起的 tailscaled/sshd`。将 `ubuntu` 行说明从 `平台创建；在 sudo 组但密码 LOCKED（无法用密码 sudo）` 换成 `Cloud Agent 交互默认用户（exec-daemon、工作区、桌面）与 SSH 登录入口；密码 LOCKED；NOPASSWD sudo`。将表后「Cloud Agent 核心进程（pod-daemon、exec-daemon、cursor-server）均以 root 运行」换成「交互会话与 exec-daemon 为 ubuntu；PID 1 / pod-daemon / tailscaled / sshd 仍为 root。详见 [`2026-09-14` §2.4](2026-09-14-luckfox-cloudagent-default-user-design.md)」。§3.2 其余 sudoers 段落保留。

- [x] **Step 4: 改 08-30 spec Q8 中同一组字符串**

将 Q8「用户选择」里的 `environment.json` 只保留 `bash .cursor/start.sh` 与 `bash .cursor/install.sh` 改为 `sudo -n -E bash .cursor/start.sh` 与 `sudo -n -E bash .cursor/install.sh`。Q8 其余 fail-fast / 禁止 `set -x` 正文不动。

- [x] **Step 5: 静态核对**

```bash
set -euo pipefail
python3 - <<'PY'
import json
from pathlib import Path
p = json.loads(Path(".cursor/environment.json").read_text())
assert "user" not in p
assert p["install"] == "sudo -n -E bash .cursor/install.sh"
assert p["start"] == "sudo -n -E bash .cursor/start.sh"
PY
grep -n '默认会话用户为 `ubuntu`' AGENTS.md
if grep -n 'sudo -n -E' AGENTS.md; then exit 1; fi
if grep -n '2026-09-14' AGENTS.md; then exit 1; fi
if grep -nE '字段只调用 `bash \.cursor/install\.sh`' AGENTS.md; then exit 1; fi
if grep -nE 'environment.json.install` 为 `bash \.cursor/install\.sh`' docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md; then exit 1; fi
if grep -nF 'Agent 实际运行用户（PID 1、编译、Tailscale 等）' docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md; then exit 1; fi
```

Expected: python 退出 0；`AGENTS.md` 命中 `默认会话用户为 \`ubuntu\``；四个 `if grep` 不命中（不进入 `exit 1`）。

- [x] **Step 6: 把 F7 文本合进实现提交**

`AGENTS.md` 与 08-30 spec 的 F7 改动合进第一个提交（实现），保留其 AuthorDate。不要新建第三个提交。

### Task 3: 验收（已完成）

**Files:** 验证 `.cursor/*`；通过标准见 Spec §5；实测值回填本 plan「最终验证证据」。

**Interfaces:** 消费 Task 1 的 draft Build；V8 在目标 Agent 上不以 sudo 调用 `./build.sh`。

- [x] **Step 1: 静态 V3 / V4**（仓库文件已满足：JSON 无 `user`、末指令 `USER ubuntu`、备选有 `useradd`）
- [x] **Step 2: 活动镜像 V1 / V2 / V5 / V6 / V7**（`bld-20260912-2957aa34-…` / `bld-20260914-5e24bf83-…`；数值见「最终验证证据」）
- [x] **Step 3: 备选镜像 useradd**（无 `useradd` → `TERMINAL_FAILURE`；有则 `whoami=ubuntu`；数值见「最终验证证据」）
- [x] **Step 4: V8 编译回归**

在 snapshot 已含本分支 Dockerfile + JSON 的 draft Build 冷启动 Agent 上执行：

```bash
set -euo pipefail
test "$(whoami)" = ubuntu
printf '4\n0\n0\n' | ./build.sh lunch
./build.sh kernel
```

Expected: 两步退出码 0；不以 sudo 调用 `./build.sh`。若 `./build.sh`(kernel) 改写了跟踪文件，按 `AGENTS.md` 用 `git checkout --` 恢复后再核对 `git status --short`。

- [x] **Step 5: 回填**

只把可复现命令与实测值写入本 plan「最终验证证据」。V8 通过后把 Spec 文首状态改为已实施（实现 plan 见本文件），不写评审过程。

---

## Execution Handoff

无剩余施工。Task 1–3 均已完成。验收须绑定 snapshot 已含当前 Dockerfile / `environment.json` / `install.sh` 的 draft Build。

## 完成情况总结

| 交付物 | 状态 |
| --- | --- |
| Task 1 运行时（Dockerfile `USER ubuntu`、JSON `sudo -n -E`、grilling `chown`） | ✅ |
| Task 2 F7（`AGENTS.md` 会话用户句、08-30 spec 指针） | ✅ |
| Task 3 验收 V1–V8 | ✅ |
| spec + plan | ✅ |

**整体结论**：Cloud Agent 交互默认用户为 `ubuntu`；`install`/`start` 仍以 root 执行特权步骤。活动与备选镜像均已在 draft Build 上通过 Spec §5 的 V1–V8（含负向门禁）。规格已实施。

## 最终验证证据

通过标准见 Spec §5。未记录任何 Secret 内容。sudo `-n` / `-E` / `-H` 下 `$HOME` 见 Spec §2.6。

### 活动镜像目标态（V1–V7）

Dockerfile 末尾 `USER ubuntu`，JSON 无 `user`，`install`/`start` 为 `sudo -n -E bash .cursor/*.sh`。Build [`bld-20260912-2957aa34-5211-416a-bf60-30089760fa3c`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260912-2957aa34-5211-416a-bf60-30089760fa3c) `SUCCEEDED`；冷启动 `bc-537e4468-e6c3-595d-bfec-33118939c710`。

| 项 | 值 |
| --- | --- |
| `whoami` / `id -u` / `HOME` | `ubuntu` / `1000` / `/home/ubuntu` |
| `stat -c '%U:%G' /workspace` | `ubuntu:ubuntu` |
| `start-user.status` | `0` |
| sshd | `0.0.0.0:22` 监听 |
| JSON `user` | 缺省（文件中无该键） |
| 进程分工 | 与 Spec §2.4 一致：root 为 tini / pod-daemon / tailscaled / sshd；ubuntu 为 exec-daemon `node`、Agent bash、desktop-init 与 VNC/XFCE；`messagebus` 跑系统 dbus |

grilling `chown -R ubuntu:ubuntu "$HOME/.cursor/skills"`：Build [`bld-20260914-5e24bf83-5724-4420-9878-374d5bd73267`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260914-5e24bf83-5724-4420-9878-374d5bd73267) `SUCCEEDED` / `bc-f468642b-cdda-5775-bfd6-889a44b60f7f`。

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

### 负向与对照

缺 `sudo -n -E`（仅 `USER ubuntu` + `bash .cursor/install.sh`）：Build [`bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260912-4d178f7c-cbbe-4a89-8976-4bd2b68850e9) `INSTALL_FAILED`；`apt-get update` 报 `E: List directory /var/lib/apt/lists/partial is missing`，apt 退出码 100。工作区 clone 在失败前已是 `ubuntu:ubuntu`。

仅 JSON `"user": "ubuntu"`、无镜像 `USER`、同样 `sudo -n -E`：Build [`bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260910-2d4076c6-9e68-4d59-a2d8-810c6e8183a9) `SUCCEEDED`；`bc-558191bf-a55d-5367-a647-a1bcc6e01892` 的 `whoami` 亦为 `ubuntu`。该路径能满足 Spec F1，但不满足 N3，故不采用。

`$HOME` 落盘、仅 chown `grilling` 子目录：Build [`bld-20260914-fe2cfdda-7915-4992-b21d-77668da58439`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260914-fe2cfdda-7915-4992-b21d-77668da58439) / `bc-d81aa084-2998-5c6f-ab15-b764afe60840`。`/home/ubuntu/.cursor/skills` 为 `750 root:root`；ubuntu 无 sudo 读 grilling 为 `Permission denied`（无法 traverse 父目录）。

### 账号与 root grilling 路径

root 身份 Build 遗留路径，Run `bc-8b3d43cb-d3cb-4a47-abec-60f947961fe9`：

| 命令 | 结果 |
| --- | --- |
| `getent passwd \| wc -l` | `25` |
| `stat -c '%a %U:%G' /root/.cursor/skills` | `750 root:root` |
| `su -s /bin/bash ubuntu -c 'cat /root/.cursor/skills/grilling/SKILL.md'` | `Permission denied` |
| `su -s /bin/bash ubuntu -c 'head -1 /cursor/stores/user/skills/grilling/SKILL.md'` | 可读（fuse 用户仓库，不是 install 交付物） |

活动镜像 + install 后交互用户仅 `root` 与 `ubuntu`。`sync`（UID 4）不是交互用户。其余 nologin：

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

### 备选官方镜像

`environment.json` 的 `dockerfile` 指向 `.cursor/Dockerfile.luckfox_pico`：

| 配置 | Environment Build | 结果 |
| --- | --- | --- |
| 仅 `USER ubuntu`，无 `useradd` | [`bld-20260915-3835d6e3-1d40-48ad-a770-493ff22f6056`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260915-3835d6e3-1d40-48ad-a770-493ff22f6056) | docker 层退出 0；Build `TERMINAL_FAILURE` |
| `useradd` 回退后 `USER ubuntu` | [`bld-20260915-ed577320-9fab-4f13-bab7-dbd1150edf8f`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260915-ed577320-9fab-4f13-bab7-dbd1150edf8f) `SUCCEEDED` | `useradd` 层 4.59kB；install 退出 0 |

有 `useradd` 的冷启动 `bc-ff8605c8-d37f-50fa-a064-6eb690b84de4`：`whoami` / `id -u` / `HOME` 为 `ubuntu` / `1000` / `/home/ubuntu`；`getent passwd ubuntu` 为 `ubuntu:x:1000:1000::/home/ubuntu:/bin/bash`；`id` 附加组仅 `ubuntu`（无活动镜像的 `adm,sudo,...`）；`sudo -n whoami` 仍为 `root`；`start-user.status` 为 `0`。

### V8 编译回归

draft Environment Build [`bld-20260915-b409b583-7eb5-4ac6-8fb0-de73165ce734`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260915-b409b583-7eb5-4ac6-8fb0-de73165ce734) `SUCCEEDED`（`refs` = `cursor/default-ubuntu-user-1fe9`）冷启动 `bc-0b1114b9-4801-59bf-9aaf-6866de29b677`：

```bash
set -euo pipefail
test "$(whoami)" = ubuntu
printf '4\n0\n0\n' | ./build.sh lunch
./build.sh kernel
```

- `whoami` / `id -u` / `HOME`：`ubuntu` / `1000` / `/home/ubuntu`
- `/tmp/cursor/start-user/start-user.status`：`0`
- lunch：退出码 0；选板 `RV1106_Luckfox_Pico_Pro_Max` + `SD_CARD` + Buildroot
- kernel：退出码 0；不以 sudo 调用 `./build.sh`
- `boot.img`：`/workspace/output/image/boot.img` 3653120 bytes，属主 `ubuntu:ubuntu`
- `git status --short`：空（未改写跟踪文件，无需 `git checkout` 恢复）

## 与计划的偏离及原因

- controller 本会话绑在旧 root 快照，V8 改在上述 draft Build 冷启动 Agent 上执行。
- `AGENTS.md` 入口句只写默认会话用户为 `ubuntu`（`HOME=/home/ubuntu`）与编译不要额外 `sudo`，不抄 `environment.json` 的 `install`/`start` 命令、不链 spec。`install`/`start` 字符串以 `.cursor/environment.json` 与 08-30 spec 为准。
- 实测 Build ID 与命令结果只写本 plan「最终验证证据」；Spec §5 只保留通过标准。
