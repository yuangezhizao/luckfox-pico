# Luckfox Pico Cloud Agent Tailscale 远程接入实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Luckfox Pico Cursor Cloud Agent 中以 Tailscale kernel 模式持久化远程接入，使 Mac 可通过 tailnet 使用 OpenSSH、noVNC、TigerVNC 和 Agent 网络代理，同时保留单活动 Pod 子网宣告与知情接受的 exit node 宣告。

**Architecture:** `.cursor/Dockerfile` 在公开基础镜像层安装当时的 Tailscale 稳定版并配置 `ubuntu` 免密 sudo；`.cursor/install.sh` 在私有 Build 快照中安装 OpenSSH；`.cursor/start.sh` 在每个 Agent Run 内以 fail-fast 顺序启动 kernel-mode `tailscaled`、收敛 Serve、注入 SSH 公钥并启动 sshd。`.cursor/environment.json` 只保留 `bash .cursor/install.sh` 与 `bash .cursor/start.sh`。`AGENTS.md` 只记录当前运维结论、端口边界和验收入口；Secrets、路由批准与 exit node 启用留在 Cursor/Tailscale 管理面。

**Tech Stack:** Cursor Cloud Agent Dockerfile/Build/`environment.json`、Ubuntu 24.04、Bash、Tailscale CLI/LocalAPI/Serve/kernel TUN、OpenSSH 9.6p1、MagicDNS、macOS Tailscale、Luckfox Pico SDK `./build.sh`。

**Spec:** [`docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`](../specs/2026-08-30-luckfox-cloudagent-tailscale-design.md)

## Global Constraints

- 使用现有分支 `cursor/luckfox-cloudagent-tailscale-spec-5ff8`，PR #8 base 为 `dev`；直接使用当前工作树，不创建 worktree。
- 仅修改 `.cursor/Dockerfile`、`.cursor/environment.json`、`.cursor/install.sh`、`.cursor/start.sh`、`AGENTS.md`、执行回填时的本 plan，以及实施完成时 Spec 的状态字段；不修改 `.cursor/Dockerfile.luckfox_pico`、`./build.sh`、板上固件、Tailscale policy/ACL/grants 或 Cursor 平台脚本。
- Tailscale 目标态固定为 kernel 模式：`tailscaled` 不带 `--tun=userspace-networking`，必须存在 `/sys/class/net/tailscale0`；userspace 只作为故障回退，不在本 plan 实现。
- Tailscale 通过官方 Ubuntu 24.04 Noble stable apt 仓库安装执行时的稳定版，不锁定版本；验证证据必须记录 `tailscale version` 与 `tailscale version --daemon`。
- Cursor Secrets 固定为 `TAILSCALE_AUTHKEY` 和 `SSH_AUTHORIZED_KEYS`，两者不得进入 git、日志、plan 或提交信息；hostname 使用 bcId UUID 第一段，来源优先 `CURSOR_CONVERSATION_ID`，否则 `/run/agent-store-fuse/self-store-id`。
- Auth key 使用 Reusable + 非 Ephemeral；用户身份节点的 node key 默认 180 天到期，重新认证前轮换 Auth key，或提前在 Admin Console 关闭该节点的 node key expiry。
- `tailscaled` 保留 `127.0.0.1:1054` HTTP 与 `127.0.0.1:1055` SOCKS5 出站代理；Serve 目标态只能包含 5901、1054、1055 三个 TCP 转发。
- OpenSSH 仅允许 `ubuntu` 公钥登录，`PasswordAuthentication no`、`PermitRootLogin no`；不配置 Tailscale SSH，不配置 Serve :22，不在 `start.sh` 中生成缺失的 host key。
- 所有 Agent 均宣告 `172.30.0.0/24`，但同一时间只批准一个 Agent 的该路由；多 Agent 并发访问使用各自 MagicDNS hostname/Tailscale IP，当前不实现 4via6。
- 节点宣告 `0.0.0.0/0` 与 `::/0`，但 Cursor 官方不支持本用法；只验收 `offers exit node` 和 Admin Console 启用状态，不承诺 exit node 数据面成功。
- 当前不配置 ACL/grants；接受获准 tailnet 设备可连接 Agent 上监听 `0.0.0.0`/`*` 的 Docker API 和 Cursor 平台端口，以及经 Serve 使用 1054/1055 代理的风险。
- 当前工作树存在无关的 kernel/toolchain 修改和未跟踪文件；每次 `git add`、`git diff --check`、提交与状态核对都必须限定到本任务路径。
- 执行 plan 时只允许在“最终验证证据”和“与计划的偏离及原因”中回填可复现命令与实测值，不在 Spec、AGENTS 或提交信息中记录操作流水。
- Cursor Environment Build 在各仓库 default branch 上 clone 再执行 `install`；功能分支 Agent 复用当前 active Build 磁盘再 checkout。推送本分支不会让 Configuration change Build 使用本 PR 的 Dockerfile。对本分支镜像/`install` 的验收必须用 `refs` 指向 `cursor/luckfox-cloudagent-tailscale-spec-5ff8` 的 draft Build。若当前 Agent 启动自旧 Build，则在运行 `start` 前于该 VM 执行与 Dockerfile 相同的 Tailscale 与 sudoers 安装命令。
- 所有多命令验证块以 `set -euo pipefail` 开头；负向检查写成 `if cmd; then exit 1; fi`（bash 对 `! cmd` 不触发 `set -e`）。
- `git cz` 提交主题使用仓库既有格式 `type(scope): <gitmoji> subject`；body 用 `- ` 并列 why，末尾只留一个 `详见 spec §X` 指针。

---

## File Structure

| 文件 | 责任 |
| --- | --- |
| `.cursor/Dockerfile` | 在活动 Ubuntu 24.04 镜像中安装浮动稳定版 Tailscale，并固化 `ubuntu` 的 NOPASSWD sudo；不安装 OpenSSH server |
| `.cursor/environment.json` | `install` / `start` 分别调用 `bash .cursor/install.sh` 与 `bash .cursor/start.sh` |
| `.cursor/install.sh` | Build 期下载 grilling skill 并安装 OpenSSH server |
| `.cursor/start.sh` | 每个 Agent Run 执行 Secret 门禁、hostname 解析、forwarding、tailscaled、`tailscale up`、Serve、authorized_keys 与 sshd 启动链 |
| `AGENTS.md` | 记录 Tailscale 当前目标态、Secrets、访问入口、端口边界、单活动 Subnet 规则、exit node 限制和验证命令入口 |
| `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` | 设计依据；实施完成且 V1–V10 闭合后只更新生命周期状态，不写评审或修订过程 |
| `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md` | 实施步骤、验证判据，以及执行后的证据与获批偏离 |

### Task 1: 实现 Cloud Agent 镜像与生命周期配置

**Files:**

- Modify: `.cursor/Dockerfile`
- Modify: `.cursor/environment.json`
- Create: `.cursor/install.sh`
- Create: `.cursor/start.sh`

**Interfaces:**

- Consumes: Cursor Build 的 `install` 阶段、Agent Run 的 `start` 阶段、Secrets `TAILSCALE_AUTHKEY`/`SSH_AUTHORIZED_KEYS`、`CURSOR_CONVERSATION_ID` 或 `/run/agent-store-fuse/self-store-id`。
- Produces: `/usr/bin/tailscale`、`/usr/sbin/tailscaled`、`/usr/sbin/sshd`、`/var/run/tailscale/tailscaled.sock`、`tailscale0`、Serve 5901/1054/1055、`/home/ubuntu/.ssh/authorized_keys` 和 `0.0.0.0:22`。

- [ ] **Step 1: 更新 `.cursor/Dockerfile` 的当前结论与 Tailscale 安装层**

把文件头中“未来要装 Tailscale / cloudflared，按官方 userspace 方式启动”的旧说明替换为当前结论：本仓安装 Tailscale，Agent Run 按 Spec §2.1 使用 kernel 模式；Cursor 官方 userspace 路径只作回退。在现有 apt 清单中补入 `iproute2 procps jq tcpdump`，分别为 `ss`、`pgrep`、JSON 验证和 V10 抓包提供可复现依赖；随后加入：

```dockerfile
# Tailscale 使用官方 Ubuntu 24.04 Noble stable apt 仓库，不锁定版本；节点认证只在 Agent Run 的 start 阶段进行。
RUN install -d -m 0755 /usr/share/keyrings \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
       -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
       -o /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# Cursor 平台在运行时提供 ubuntu 用户；为 OpenSSH 登录后的提权固化免密 sudo，不在此镜像层安装 openssh-server。
RUN printf '%s\n' 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu \
    && visudo -cf /etc/sudoers.d/ubuntu
```

同时把“不装 openssh-server”的注释收敛为：公开 Dockerfile 层不安装 server，server 由 `.cursor/install.sh` 写入私有 Build 快照，避免公开镜像复用同一 host key。

- [ ] **Step 2: 写入 `.cursor/install.sh` 并缩短 `environment.json.install`**

将下列内容写入 `.cursor/install.sh`（`#!/bin/bash`、`set -euo pipefail`），grilling 下载命令保持原有字节；任一步失败都会让 Build 失败：

```sh
#!/bin/bash
set -euo pipefail

curl --fail --location --max-redirs 3 --proto "=https" --tlsv1.2 --retry 3 --retry-max-time 120 --connect-timeout 15 --max-time 90 --create-dirs --output "$HOME/.cursor/skills/grilling/SKILL.md" "https://raw.githubusercontent.com/mattpocock/skills/85f83d3fde1d3a90d5c9a657f6998c79a6c37308/skills/productivity/grilling/SKILL.md"
apt-get update
apt-get install -y openssh-server
rm -rf /var/lib/apt/lists/*
```

`environment.json.install` 只保留 `bash .cursor/install.sh`。允许 apt 安装 `openssh-server` 推荐的 `libpam-systemd`（或其他 logind provider）、`ncurses-term`、`ssh-import-id`、`xauth` 及其依赖；不得把 `openssh-server` 移入 Dockerfile，也不得加入 host key 缺失时调用 `ssh-keygen -A` 的逻辑。

- [ ] **Step 3: 写入 `.cursor/start.sh` 并缩短 `environment.json.start`**

将启动链写入 `.cursor/start.sh`（`#!/bin/bash`、`set -euo pipefail`）；`environment.json.start` 只保留 `bash .cursor/start.sh`。hostname 优先 `CURSOR_CONVERSATION_ID`，否则读 `/run/agent-store-fuse/self-store-id`。完整脚本见仓库文件；不得把启动链再内联进 JSON。

`tailscaled` 不显式传入 `--socket`，使用 Linux 默认的 `/var/run/tailscale/tailscaled.sock`，就绪检查仍读取该默认路径。`start.sh` 不导出代理变量到后续 shell；需要显式代理的进程按 AGENTS 指引自行设置，kernel 模式下普通 tailnet 出站仍走透明路由。

- [ ] **Step 4: 静态验证 Dockerfile、JSON、shell 与 Secret 边界**

Run:

```bash
set -euo pipefail
docker build --check -f .cursor/Dockerfile .
grep -F 'noble.tailscale-keyring.list' .cursor/Dockerfile
grep -F 'apt-get install -y tailscale' .cursor/Dockerfile
jq -e '.build.dockerfile == "Dockerfile" and .build.context == ".." and .install == "bash .cursor/install.sh" and .start == "bash .cursor/start.sh"' .cursor/environment.json
bash -n .cursor/install.sh
bash -n .cursor/start.sh
grep -F 'skills/productivity/grilling/SKILL.md' .cursor/install.sh
grep -F 'apt-get install -y openssh-server' .cursor/install.sh
grep -F -- '--advertise-routes=172.30.0.0/24' .cursor/start.sh
grep -F -- '--advertise-exit-node' .cursor/start.sh
grep -F 'tailscale serve reset' .cursor/start.sh
grep -F '/usr/sbin/sshd -t' .cursor/start.sh
grep -F '/run/agent-store-fuse/self-store-id' .cursor/start.sh
if grep -F -- '--tun=userspace-networking' .cursor/start.sh; then exit 1; fi
if grep -E -- '--state(dir)?=' .cursor/start.sh; then exit 1; fi
auth_key_pattern='tskey''-auth-'
private_key_pattern='BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE'' KEY'
pkcs8_pattern='BEGIN PRIVATE'' KEY'
ssh_pub_pattern='ssh-ed25519'' |ssh-rsa'' |ssh-dss'' |ecdsa-sha2''-'
if git grep -nF "$auth_key_pattern" -- .cursor AGENTS.md docs/superpowers; then exit 1; fi
if git grep -nE "$private_key_pattern" -- .cursor AGENTS.md docs/superpowers; then exit 1; fi
if git grep -nF "$pkcs8_pattern" -- .cursor AGENTS.md docs/superpowers; then exit 1; fi
if git grep -nE "$ssh_pub_pattern" -- .cursor AGENTS.md docs/superpowers; then exit 1; fi
git diff --check -- .cursor/Dockerfile .cursor/environment.json .cursor/install.sh .cursor/start.sh
```

Expected: Dockerfile check 无错误；官方 Noble stable 仓库与未锁版本的 apt 安装命令均存在；`jq`、`bash -n` 和所有正向 `grep` 退出码为 0；负向检查无匹配；目标文件无空白错误。

- [ ] **Step 5: 提交运行时配置**

```bash
git add -- .cursor/Dockerfile .cursor/environment.json .cursor/install.sh .cursor/start.sh
git diff --cached --check
git diff --cached --name-status
git cz
```

提交主题使用单一主题 `chore(cloud-agent): 🔧 configure Tailscale remote access`；body 记录采用 kernel 目标态、OpenSSH 进入私有 Build 快照和 fail-fast 启动链的原因，末尾只保留 `详见 spec §2–§8` 指针。

### Task 2: 更新 Cloud Agent 运维说明

**Files:**

- Modify: `AGENTS.md`

**Interfaces:**

- Consumes: Task 1 的实际 `.cursor` 配置和 Spec §2、§4、§7。
- Produces: 后续 Agent 可直接执行的访问入口、端口边界和验证约束；不复制完整 Spec 或历史命令输出。

- [ ] **Step 1: 在 `AGENTS.md` 的 Cloud Agent 环境章节后加入 Tailscale 当前态**

加入以下信息，保持单句不硬折行：

```markdown
### Tailscale 远程接入

- 活动 Cloud Agent 在每个 Agent Run 由 `bash .cursor/start.sh` 启动 Tailscale **kernel 模式**（存在 `tailscale0`，不带 `--tun=userspace-networking`）；Cursor 官方 userspace 方案仅作兼容回退。
- 必需 Cursor Secrets：`TAILSCALE_AUTHKEY`（Reusable、非 Ephemeral）和 `SSH_AUTHORIZED_KEYS`；不得写入仓库。Auth key 最长 90 天，用户身份节点的 node key 默认 180 天，重新认证前需轮换 Auth key 或提前关闭节点 key expiry。
- 节点名为 `cursor-agent-<bcId UUID 第一段>`。`bcId` 优先取 `CURSOR_CONVERSATION_ID`；平台 `start` 未注入该变量时改读 `/run/agent-store-fuse/self-store-id`（与 bcId 相同）。实际名称与 Tailscale IP 以 `tailscale status` 为准。
- OpenSSH 使用 `ubuntu` 公钥登录并可免密 sudo；Tailscale SSH 禁用。SSH 和 noVNC 分别使用 `<hostname>:22`、`http://<hostname>:26058`；TigerVNC 使用 `<hostname>:5901`。
- Agent 内显式访问 tailnet HTTP(S) 服务可设置 `HTTP_PROXY=http://localhost:1054/`、`HTTPS_PROXY=http://localhost:1054/` 或 `ALL_PROXY=socks5h://localhost:1055/`；Mac 也可按需把 `<hostname>:1054` / `<hostname>:1055` 作为 HTTP / SOCKS5 代理。
- 所有 Agent 宣告 `172.30.0.0/24`，但同一时间只在 Tailscale Admin Console 批准一个 Agent 的该路由；并行 Agent 必须用各自 hostname/Tailscale IP 访问，不用 `172.30.0.2` 区分。
- 节点同时宣告 exit node；Cursor 官方不支持此用途，当前只要求 Admin Console 显示并启用该能力，不承诺实际转发成功。

| 端口 | 绑定/路径 | 用途与边界 |
| --- | --- | --- |
| 22 | `0.0.0.0` | OpenSSH，tailnet 天然可达，不配置 Serve |
| 1054/1055 | `127.0.0.1` + Serve | Tailscale HTTP/SOCKS5 代理，Agent 本地及 Mac 按需使用 |
| 5901 | `127.0.0.1` + Serve | TigerVNC，无密码，仅供获准 tailnet 设备使用 |
| 26058 | `0.0.0.0` | noVNC，tailnet 天然可达，不配置 Serve |
| 2375、26053–26055、26500、50052 | `0.0.0.0`/`*` | Cursor/Docker 平台端口，kernel 模式下天然可达；当前不配置 ACL，接受 Spec §2.8 的风险 |
| Peer API 与 WireGuard UDP | Tailscale IP/动态端口 | 端口会变化，不写死到配置或检查脚本 |

完整设计、官方支持边界、端口实测和 V1–V10 验收见 `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`。
```

- [ ] **Step 2: 校验 AGENTS 与实现保持一致且没有过程痕迹**

Run:

```bash
set -euo pipefail
grep -F 'kernel 模式' AGENTS.md
grep -F 'TAILSCALE_AUTHKEY' AGENTS.md
grep -F 'SSH_AUTHORIZED_KEYS' AGENTS.md
grep -F '同一时间只在 Tailscale Admin Console 批准一个 Agent' AGENTS.md
grep -F '2375、26053–26055、26500、50052' AGENTS.md
grep -F 'docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md' AGENTS.md
if grep -E 'Review 发现|据实测改写|已更正|第[一二三四五六七八九十]+次' AGENTS.md; then exit 1; fi
git diff --check -- AGENTS.md
```

Expected: 六个正向检查各命中当前结论；过程痕迹检查无匹配；无空白错误。

- [ ] **Step 3: 提交运维说明**

```bash
git add -- AGENTS.md
git diff --cached --check
git diff --cached --name-status
git cz
```

提交主题使用 `docs(cloud-agent): 📝 document Tailscale access boundaries`；body 只记录后续 Agent 需要明确访问入口、动态端口和无 ACL 信任边界的原因，末尾保留 `详见 spec §2.8、§4、§7`。

### Task 3: 验证 Build、启动门禁与 Agent 本机目标态

**Files:**

- Verify: `.cursor/Dockerfile`
- Verify: `.cursor/environment.json`
- Backfill after execution: `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md`

**Interfaces:**

- Consumes: Task 1–2 的已推送提交、Cursor Secrets、从该分支创建的新 Cloud Agent。
- Produces: Spec V1–V3、V5、V8–V9 的可复现 Agent 端证据，以及 `TAILSCALE_HOST`/Tailscale IP 供 Task 4 使用。

- [ ] **Step 1: 推送实现提交并对本分支触发 draft Build**

```bash
set -euo pipefail
git status --short
git push origin HEAD:refs/heads/cursor/luckfox-cloudagent-tailscale-spec-5ff8
```

使用 Cursor Cloud MCP `trigger-environment-build`，`refs` 为 `[{ "repoUrl": "github.com/yuangezhizao/luckfox-pico", "ref": "cursor/luckfox-cloudagent-tailscale-spec-5ff8" }]`。用 `list-environment-builds` 轮询到该 Build `SUCCEEDED`（失败则停止，不进入 V1–V10）。draft Build 只证明本分支 Dockerfile 与 `install` 能产出快照，不会自动变成后续 Agent 的 active 启动镜像。

当前验收 Agent 若启动自旧 active Build，则在执行 `start` 前于本机按 Dockerfile 相同字节安装 Tailscale（Noble stable 仓库、未锁版本）并写入 `ubuntu` NOPASSWD sudoers，使后续 V1–V10 验证的是本 PR 的启动链，而不是旧镜像缺二进制。不得把「已 push 功能分支」当成 Configuration change Build 已包含新 Dockerfile。

在 Cursor Cloud Agents 环境中确认 User Secrets `TAILSCALE_AUTHKEY` 与 `SSH_AUTHORIZED_KEYS` 均已注入当前 Agent 且非空后，再执行 `start`；Expected: `start` 退出码 0。Secrets 缺失时只做 Step 2 的门禁，不把半初始化状态当成 V1 通过。

- [ ] **Step 2: 验证缺失 Secret 时在副作用前失败**

在当前 Agent 中执行（不要求已经成功跑过 `start`）：

```bash
set -euo pipefail
before_tailscaled="$(pgrep -xc tailscaled 2>/dev/null || true)"
before_sshd="$(pgrep -xc sshd 2>/dev/null || true)"
: "${before_tailscaled:=0}"
: "${before_sshd:=0}"
before_forward_v4="$(sysctl -n net.ipv4.ip_forward)"
before_forward_v6="$(sysctl -n net.ipv6.conf.all.forwarding)"
if [ -f /etc/sysctl.d/99-tailscale.conf ]; then
  before_sysctl_mtime="$(stat -c '%y' /etc/sysctl.d/99-tailscale.conf)"
else
  before_sysctl_mtime=ABSENT
fi
if before_serve="$(tailscale serve status --json 2>/dev/null | jq -S .)"; then
  :
else
  before_serve=UNAVAILABLE
fi
if env -u TAILSCALE_AUTHKEY bash .cursor/start.sh; then exit 1; fi
if TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-gate-only}" env -u SSH_AUTHORIZED_KEYS bash .cursor/start.sh; then exit 1; fi
test "$(pgrep -xc tailscaled 2>/dev/null || true)" = "$before_tailscaled"
test "$(pgrep -xc sshd 2>/dev/null || true)" = "$before_sshd"
test "$(sysctl -n net.ipv4.ip_forward)" = "$before_forward_v4"
test "$(sysctl -n net.ipv6.conf.all.forwarding)" = "$before_forward_v6"
if [ "$before_sysctl_mtime" = ABSENT ]; then
  test ! -e /etc/sysctl.d/99-tailscale.conf
else
  test "$(stat -c '%y' /etc/sysctl.d/99-tailscale.conf)" = "$before_sysctl_mtime"
fi
if [ "$before_serve" = UNAVAILABLE ]; then
  if tailscale serve status --json >/dev/null 2>&1; then exit 1; fi
else
  test "$(tailscale serve status --json | jq -S .)" = "$before_serve"
fi
```

`gate-only` 只用于在 `TAILSCALE_AUTHKEY` 本身为空时让第二个调用到达 `SSH_AUTHORIZED_KEYS` 展开，不是 Auth key，不得用于 `tailscale up`。Expected: 两次调用均非零退出，进程计数、forwarding、sysctl 文件与 Serve 均不变；不得输出 Secret 内容。结合 `start` 的静态顺序确认两个参数展开位于首个副作用命令之前。

- [ ] **Step 3: 验证 forwarding、kernel 模式、LocalAPI 与版本**

```bash
set -euo pipefail
test "$(sysctl -n net.ipv4.ip_forward)" = 1
test "$(sysctl -n net.ipv6.conf.all.forwarding)" = 1
test -S /var/run/tailscale/tailscaled.sock
timeout 5s tailscale status --json >/dev/null
tailscale ip -4 | grep -q '^100\.'
pid="$(pgrep -xo tailscaled)"
test -r "/proc/${pid}/cmdline"
test -d /sys/class/net/tailscale0
if tr '\0' ' ' < "/proc/${pid}/cmdline" | grep -q -- '--tun=userspace-networking'; then exit 1; fi
tailscale version
tailscale version --daemon
```

Expected: 所有断言退出码为 0；记录 client 与 daemon 版本、实际 hostname、Tailscale IPv4 和完整 `tailscaled` 参数，但不记录 Auth key。

- [ ] **Step 4: 验证本地代理与 Serve 声明式收敛**

```bash
set -euo pipefail
sudo ss -H -ltnp | awk '$4 == "127.0.0.1:1054" && /"tailscaled"/ { found=1 } END { exit !found }'
sudo ss -H -ltnp | awk '$4 == "127.0.0.1:1055" && /"tailscaled"/ { found=1 } END { exit !found }'
TAILSCALE_PROXY_TEST_URL=http://llm
curl --fail --silent --show-error --output /dev/null --noproxy '' --proxy http://localhost:1054 "$TAILSCALE_PROXY_TEST_URL"
curl --fail --silent --show-error --output /dev/null --noproxy '' --proxy socks5h://localhost:1055 "$TAILSCALE_PROXY_TEST_URL"
tailscale serve --bg --tcp 10080 tcp://127.0.0.1:9
tailscale serve reset
tailscale serve --bg --tcp 5901 tcp://127.0.0.1:5901
tailscale serve --bg --tcp 1054 tcp://127.0.0.1:1054
tailscale serve --bg --tcp 1055 tcp://127.0.0.1:1055
tailscale serve status --json
tailscale serve status
```

Expected: 两个代理请求成功；最终 Serve 只含 5901、1054、1055，10080 和其他额外转发均不存在。

- [ ] **Step 5: 验证 OpenSSH、sudo 与路由宣告**

```bash
set -euo pipefail
test "$(stat -c '%a %U:%G' /home/ubuntu/.ssh)" = '700 ubuntu:ubuntu'
test "$(stat -c '%a %U:%G' /home/ubuntu/.ssh/authorized_keys)" = '600 ubuntu:ubuntu'
test -s /home/ubuntu/.ssh/authorized_keys
test "$(stat -c '%a %U:%G' /run/sshd)" = '755 root:root'
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T | grep -Fx 'passwordauthentication no'
sudo /usr/sbin/sshd -T | grep -Fx 'permitrootlogin no'
ss -H -ltnp | awk '$4 == "0.0.0.0:22" { found=1 } END { exit !found }'
su - ubuntu -c 'sudo whoami' | grep -Fx root
tailscale get --set-flags | tr ' ' '\n' | grep -Fx -- '--advertise-routes=172.30.0.0/24'
tailscale get --set-flags | tr ' ' '\n' | grep -Fx -- '--advertise-exit-node'
tailscale status | grep -F 'offers exit node'
```

Expected: 权限、sshd 有效配置、22 监听、免密 sudo 与两个宣告均符合 Spec；不读取或打印 `authorized_keys` 内容。

### Task 4: 验证 Mac 入站、单活动 Subnet 与 SDK 回归

**Files:**

- Verify: `AGENTS.md`
- Modify after V1–V10 pass: `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`
- Backfill after execution: `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md`

**Interfaces:**

- Consumes: Task 3 的目标 Agent hostname/Tailscale IP；Mac 已加入同一 tailnet；执行者提供该 Pod 内非 Agent 本地地址的 `SUBNET_TEST_TARGET` 与可访问的完整 `SUBNET_TEST_URL`。
- Produces: Spec V4、V6–V7、V9–V10 的跨节点证据和最终范围检查。

- [ ] **Step 1: 在 Admin Console 固化单活动路由与 exit node 状态**

在 Tailscale Admin Console 的 Machines 页面打开目标 Agent 的 route settings：启用其 `172.30.0.0/24` 和 **Use as exit node**；逐个检查其他 Cloud Agent，确保相同 `/24` 均未启用。Expected: 只有目标 Agent 是该前缀的活动 subnet router；多个 Agent 可同时保留各自 hostname/Tailscale IP。

- [ ] **Step 2: 从 Mac 验证 SSH host key、公钥登录、VNC/noVNC 与代理**

先在可信 Agent 会话记录 `sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` 的预期指纹；再在 Mac 执行：

```bash
set -euo pipefail
: "${TAILSCALE_HOST:?Set TAILSCALE_HOST to the actual MagicDNS hostname}"
TAILSCALE_PROXY_TEST_URL=http://llm
SSH_KNOWN_HOSTS="$(mktemp)"
trap 'unlink "$SSH_KNOWN_HOSTS" 2>/dev/null || true' EXIT
ssh-keyscan "$TAILSCALE_HOST" > "$SSH_KNOWN_HOSTS"
ssh-keygen -lf "$SSH_KNOWN_HOSTS"
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" "ubuntu@${TAILSCALE_HOST}" true
test "$(nc -w 5 "$TAILSCALE_HOST" 5901 | head -c 4)" = 'RFB '
curl --fail --silent --show-error --output /dev/null --noproxy '' --proxy "http://${TAILSCALE_HOST}:1054" "$TAILSCALE_PROXY_TEST_URL"
curl --fail --silent --show-error --output /dev/null --noproxy '' --proxy "socks5h://${TAILSCALE_HOST}:1055" "$TAILSCALE_PROXY_TEST_URL"
nmap -sT -Pn -p 22,1054,1055,2375,5901,26053-26055,26058,26500,50052 "$TAILSCALE_HOST"
```

人工确认 `ssh-keygen` 指纹与 Agent 端一致，并在浏览器打开 `http://${TAILSCALE_HOST}:26058`；Expected: SSH、RFB、两种代理和 noVNC 成功，扫描结果与 AGENTS 的天然可达/Serve 端口边界一致。动态 Peer API TCP 端口和 WireGuard UDP 端口只记录“存在动态端口”，不固化数值。

- [ ] **Step 3: 验证单活动 Subnet 的 kernel 数据面**

当前 Pod 的 `172.30.0.0/24` 内，除 Agent `172.30.0.2` 外没有稳定应答主机（网关 `172.30.0.1` ARP 可达但不响应 ICMP/HTTP）。在目标 Agent 创建临时隔离端点（主网络命名空间不把 `172.30.0.3` 配成本地地址）：

```bash
set -euo pipefail
ip netns add ts-v10
ip link add veth-v10h type veth peer name veth-v10n
ip link set veth-v10n netns ts-v10
ip addr add 169.254.249.1/30 dev veth-v10h
ip link set veth-v10h up
ip netns exec ts-v10 ip addr add 169.254.249.2/30 dev veth-v10n
ip netns exec ts-v10 ip addr add 172.30.0.3/32 dev lo
ip netns exec ts-v10 ip link set lo up
ip netns exec ts-v10 ip link set veth-v10n up
ip netns exec ts-v10 ip route add default via 169.254.249.1
ip route add 172.30.0.3/32 via 169.254.249.2
ip netns exec ts-v10 python3 -m http.server 80 --bind 172.30.0.3 >/tmp/ts-v10-http.log 2>&1 &
echo $! > /tmp/ts-v10-http.pid
curl --fail --silent --show-error --output /dev/null --noproxy '*' http://172.30.0.3/
ip -o route get 172.30.0.3
```

Expected: 本机经转发访问 `http://172.30.0.3/` 成功；`ip -o route get 172.30.0.3` 的出口不是把 `172.30.0.3` 显示为本机地址。导出 `SUBNET_TEST_TARGET=172.30.0.3`、`SUBNET_TEST_URL=http://172.30.0.3/`。

在目标 Agent 准备抓包：

```bash
set -euo pipefail
: "${SUBNET_TEST_TARGET:?Set a non-local target inside 172.30.0.0/24}"
egress_dev="$(ip -o route get "$SUBNET_TEST_TARGET" | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
test -n "$egress_dev"
capture_dir="$(mktemp -d)"
sudo timeout 30 tcpdump -ni tailscale0 "host ${SUBNET_TEST_TARGET}" -w "${capture_dir}/tailscale0.pcap" &
tailscale_capture_pid=$!
sudo timeout 30 tcpdump -ni "$egress_dev" "host ${SUBNET_TEST_TARGET}" -w "${capture_dir}/egress.pcap" &
eth0_capture_pid=$!
printf '%s\n' "$capture_dir" "$tailscale_capture_pid" "$eth0_capture_pid" "$egress_dev"
```

在 30 秒内从 Mac 执行：

```bash
set -euo pipefail
: "${SUBNET_TEST_TARGET:?Set the same target used on the Agent}"
: "${SUBNET_TEST_URL:?Set the complete stable test URL on that target}"
route -n get "$SUBNET_TEST_TARGET" | grep -E 'interface: +utun[0-9]+'
curl --noproxy '*' --fail --silent --show-error --output /dev/null "$SUBNET_TEST_URL"
```

回到 Agent：

```bash
set -euo pipefail
wait "$tailscale_capture_pid" || test "$?" = 124
wait "$eth0_capture_pid" || test "$?" = 124
sudo tcpdump -nn -r "${capture_dir}/tailscale0.pcap" "host ${SUBNET_TEST_TARGET}"
sudo tcpdump -nn -r "${capture_dir}/egress.pcap" "host ${SUBNET_TEST_TARGET}"
sudo unlink "${capture_dir}/tailscale0.pcap"
sudo unlink "${capture_dir}/egress.pcap"
rmdir "$capture_dir"
kill "$(cat /tmp/ts-v10-http.pid)" 2>/dev/null || true
ip route del 172.30.0.3/32 || true
ip link del veth-v10h || true
ip netns del ts-v10 || true
```

Expected: Mac 路由经 Tailscale utun 且请求成功；同一请求在目标 Agent 的 `tailscale0` 与 `ip route get` 给出的出口接口均可见，证明由该 Agent 内核转发。访问 Agent 自身 `172.30.0.2` 不计为通过。

- [ ] **Step 4: 执行 SDK 快速回归并检查污染边界**

在 Agent 中执行：

```bash
set -euo pipefail
printf '4\n0\n0\n' | ./build.sh lunch
./build.sh kernel
git status --short
```

Expected: `lunch` 与 `kernel` 退出码为 0；不执行耗时全量 rootfs/`allsave` 编译；不得新增本任务路径之外的修改。若平台启动本身造成端口或服务变化，只在 plan 验证证据中记录实测值和与 Spec 的差异，不把会过时的完整命令输出复制进 AGENTS。

- [ ] **Step 5: 回填证据、更新 Spec 生命周期并提交最终文档状态**

在本 plan 的任务末尾新增“最终验证证据”和“与计划的偏离及原因”，只记录 Task 3–4 的可复现命令、Tailscale 版本、实际 hostname/IP、端口/Serve/路由判据、SDK 回归结果及获批偏离；不记录 Secrets、完整日志或操作流水。仅当 V1–V10 全部通过时，把 Spec 顶部状态改为“已实施”，保留 plan 链接并移除“尚未实施”，同时把 Spec §10 收敛为指向本 plan 的最终验证证据；若任一验收未通过，则保持“尚未实施”并在 plan 的偏离章节记录阻塞原因。随后执行：

```bash
set -euo pipefail
git diff --check -- .cursor/Dockerfile .cursor/environment.json .cursor/install.sh .cursor/start.sh AGENTS.md docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md
git diff --name-status origin/dev...HEAD
git status --short
git add -- docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md
git diff --cached --check
git diff --cached --name-status
git cz
git push origin HEAD:refs/heads/cursor/luckfox-cloudagent-tailscale-spec-5ff8
git fetch origin cursor/luckfox-cloudagent-tailscale-spec-5ff8
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/cursor/luckfox-cloudagent-tailscale-spec-5ff8)"
git diff --name-only origin/dev...origin/cursor/luckfox-cloudagent-tailscale-spec-5ff8
```

提交主题使用 `docs(superpowers): 📝 record Tailscale validation evidence`；body 仅说明证据用于闭合 V1–V10 和记录获批偏离，末尾保留 `详见 spec §7`。推送后核对远端 HEAD 与本地一致，且相对 `origin/dev` 的文件清单只能包含 Spec、plan、`.cursor/Dockerfile`、`.cursor/environment.json`、`.cursor/install.sh`、`.cursor/start.sh` 与 `AGENTS.md`，不得带入当前工作树的其他修改。

---

## Execution Handoff

Plan 完成后，推荐使用 `superpowers:subagent-driven-development` 为 Task 1–4 分别派发新子代理并在任务间审查；若在当前会话内批量执行，则使用 `superpowers:executing-plans` 并按 Task 1–4 设置检查点。执行开始前必须先确认 Cursor User Secrets 已注入当前 Agent、Mac 已加入目标 tailnet，并对本分支触发 draft Environment Build；V10 使用 plan 给出的 `172.30.0.3` 隔离端点，不依赖执行者临时发明目标地址。

## 最终验证证据

以下结果来自分支 `cursor/luckfox-cloudagent-tailscale-spec-5ff8`，未记录任何 Secret 内容。

- draft Environment Build [`bld-20260905-16b0ffd7-cbcf-4346-aec0-e03ae21cfd0b`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260905-16b0ffd7-cbcf-4346-aec0-e03ae21cfd0b) 状态为 `SUCCEEDED`；`install` 退出码 0（含 `openssh-server`），snapshot ready。
- 新 Agent Run `bc-3656f5d6-f3f5-5fb7-9202-399345263e7c` 从该 Build cold boot。`environment.json` 的 `install`/`start` 分别为 `bash .cursor/install.sh` 与 `bash .cursor/start.sh`。PID 1 有 Secrets，无 `CURSOR_CONVERSATION_ID`。`/run/agent-store-fuse/self-store-id` 与会话 `CURSOR_CONVERSATION_ID` 字节相同。
- 平台 `start` 退出码 1，错误为 `CURSOR_CONVERSATION_ID or /run/agent-store-fuse/self-store-id is required`。`start-user.log` mtime 早于 `self-store-id` 约 3 秒。当时无 `tailscale0`、无 LocalAPI socket、无 `tailscaled`/`sshd`。同一脚本在 Agent 会话中退出码 0。
- V1（会话内 start）：`net.ipv4.ip_forward=1`，`net.ipv6.conf.all.forwarding=1`；存在 `/sys/class/net/tailscale0` 与 `/var/run/tailscale/tailscaled.sock`；`tailscaled` 命令行为 `--outbound-http-proxy-listen=localhost:1054 --socks5-server=localhost:1055`，不含 `--tun=userspace-networking`。client/daemon `1.102.3`（daemon `1.102.3-t9329c3677-ga522f65e9`）。hostname `cursor-agent-3656f5d6`，MagicDNS `cursor-agent-3656f5d6.tail093f.ts.net.`，Tailscale IPv4 `100.75.134.115`，`Online=true`。缺失 `TAILSCALE_AUTHKEY` 或 `SSH_AUTHORIZED_KEYS` 时 `start.sh` 非零退出且 `tailscaled`/`sshd` 计数不变。
- V2：`curl` 经 `127.0.0.1:1054` HTTP 与 `127.0.0.1:1055` SOCKS5 访问 `http://llm/` 均退出码 0（HTTP 302 `/chat`）。
- V3：Serve 仅 5901/1054/1055 三个 TCP 转发。
- V5 Agent 侧：`/home/ubuntu/.ssh` 为 `700 ubuntu:ubuntu`，`authorized_keys` 为 `600 ubuntu:ubuntu` 且非空；`/run/sshd` 为 `755 root:root`；`sshd -T` 含 `passwordauthentication no` 与 `permitrootlogin no`；`0.0.0.0:22` 监听。
- V8：`su - ubuntu -c 'sudo whoami'` 输出 `root`。
- V7 以 `printf '4\n0\n0\n' | ./build.sh lunch && ./build.sh kernel` 复现：Pico Max、SD card、Buildroot 选板成功，kernel 构建退出码为 0，生成 `output/image/boot.img`（3,652,096 bytes），随后 `git status --short` 无输出。
- V9 Agent 侧此前 Run 已宣告 `--advertise-routes=172.30.0.0/24` 与 `--advertise-exit-node`；Admin Console 批准未执行。
- V10 的 Agent 本地前置端点此前已创建并可 `curl http://172.30.0.3/`；Mac 路径未执行。

验收汇总：配置抽取与会话内 V1、V2、V3、V5 Agent 侧、V7、V8 通过；平台自动 start 未通过；V9 仅完成宣告、未获 Admin 批准；V4、V6、完整 V10 未执行。V1–V10 未全部通过，Spec 生命周期继续保持“尚未实施”。

## 与计划的偏离及原因

- 平台执行 `start` 时不提供 `CURSOR_CONVERSATION_ID`，且 `/run/agent-store-fuse/self-store-id` 可能尚未出现（`bc-3656f5d6-…` 上晚约 3 秒），开机自动 start 退出码 1；同一脚本在已注入 bcId 且 fuse 可读的 Agent 会话中退出码 0，节点才加入 tailnet。
- 当前执行环境不是 Mac，且没有 Tailscale Admin Console 访问能力，因此 Task 4 Step 1 的单活动 `172.30.0.0/24` 批准与 **Use as exit node** 启用状态无法核对，Task 4 Step 2 的 Mac SSH host key、公钥登录、RFB、HTTP/SOCKS5 代理、nmap 与 noVNC 浏览器检查未执行。
- V10 仅完成隔离 HTTP 端点的 Agent 本地访问和路由判据；没有 Mac 的 `utun` 路由、跨 tailnet curl 或 `tailscale0`/出口接口抓包，故保持未通过。
- SDK 回归依计划只执行非交互 `lunch` 与 `./build.sh kernel`，未执行全量 rootfs/`allsave`；构建未改写 `project/app/wifi_app/` 下的跟踪二进制，无需恢复。
- 容器内 Tailscale 报告 connmark/CONNMARK 不受支持；kernel TUN、Serve 与本地代理检查仍通过。
