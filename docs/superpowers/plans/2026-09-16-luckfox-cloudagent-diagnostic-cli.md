# Luckfox Pico Cloud Agent 诊断 CLI 软件包实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在活动与备选 Cloud Agent Dockerfile 的 SDK/工具 apt `RUN` 中补装 12 个诊断 CLI，使含本镜像的 Environment Build 冷启动后包与命令可用。

**Architecture:** 包写进 `USER ubuntu` 之前现有 SDK/工具 `RUN`，与 `htop` / `neofetch` 同层、`--no-install-recommends`。Ubuntu apt 名按 Spec §2.2；`conntrack-tools` 只出现在 AlmaLinux 对照列与注释，不写入 `apt-get install`。不改 `environment.json` / `install.sh` / `start.sh`。验收用 `refs` 指向本分支的 draft Environment Build 冷启动；当前会话若绑在旧快照，其 `dpkg-query` 不能当反例。

**Tech Stack:** `.cursor/Dockerfile`（Ubuntu 24.04）、`.cursor/Dockerfile.luckfox_pico`（Jammy 官方 FROM）、apt `--no-install-recommends`、Cursor Environment Build（`trigger-environment-build` + `refs`）。

**Spec:** [`docs/superpowers/specs/2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md`](../specs/2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md)

## Global Constraints

- 使用现有分支 `cursor/dockerfile-user-ubuntu-1fe9`，PR #10 base 为 `dev`；直接使用当前工作树，不创建 worktree。
- 相对 `origin/dev` 目标提交：实现（仅两份 Dockerfile）在前，文档（本 plan、2026-09-16 spec、2026-08-30 spec §2.3.1）单个提交在最后。
- 仅修改 `.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、`docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` 的 §2.3.1 需求集合与「因此同一需求集合…」那句写入列表、本 plan、2026-09-16 spec。不改 `environment.json`、`install.sh`、`start.sh`、`AGENTS.md`、`./build.sh`、板上固件、07-13 spec 交付物表（不枚举这 12 个包）。
- apt 清单禁止 `conntrack-tools`、`conntrackd`、`iotop-c`、`which`、`gnu-which`。不锁 apt 版本。SDK/工具 `RUN` 保持 `--no-install-recommends`。`USER ubuntu` 必须仍是两份文件的最后非空指令。
- 不引入 AlmaLinux / EPEL 仓库。对照名只写在 spec 表与 Dockerfile 注释。
- 对本分支镜像的 V1/V2/V5 必须用 `refs` = `cursor/dockerfile-user-ubuntu-1fe9` 的 draft Build；`repoUrl` 为 `github.com/yuangezhizao/luckfox-pico`。禁止对该 repo-file 环境传 `environmentJson`。绑在旧快照上的 Agent 不能当反例。不要求 `./build.sh allsave`。
- Cursor Secrets 不得进入 git、日志、plan 或提交信息。
- 执行 plan 时只允许在「最终验证证据」中回填可复现命令与实测值。Spec §5 只保留通过标准。已完成 Task 只保留步骤与文件目录。`git cz` 主题为 `type(scope): <gitmoji> subject`；body 用 `- ` 并列 why，末尾只留一个 `详见 spec §X` 指针。
- 所有多命令验证块以 `set -euo pipefail` 开头。

---

## File Structure

| 文件 | 责任 |
| --- | --- |
| `.cursor/Dockerfile` | 活动镜像 SDK/工具 `RUN` 追加 12 个 apt 包与注释 |
| `.cursor/Dockerfile.luckfox_pico` | 备选镜像同一组包与注释 |
| `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` | §2.3.1 需求集合与备选写入列表含这 12 个 apt 名 |
| `docs/superpowers/specs/2026-09-16-luckfox-cloudagent-diagnostic-cli-design.md` | 设计规格（通过标准）；实测只写本 plan |
| `docs/superpowers/plans/2026-09-16-luckfox-cloudagent-diagnostic-cli.md` | 本文件：Task、完成情况、最终验证证据 |

12 个 **Ubuntu apt 名**（写入 `RUN`）：`tree` `iftop` `iotop` `screen` `ncdu` `traceroute` `nmap` `ngrep` `conntrack` `psmisc` `fping` `dmidecode`。

### Task 1: 两份 Dockerfile 的 SDK/工具 RUN（已完成）

**落地文件（以仓库为准，不在此重复 RUN 正文）：**

- Modify: `.cursor/Dockerfile`（诊断 CLI 注释；`htop neofetch \` 后续两行 12 包）
- Modify: `.cursor/Dockerfile.luckfox_pico`（digest「不在」列表、同一注释、`iproute2 jq tcpdump \` 后续两行 12 包）

**Interfaces:** 消费 Spec §2.2 apt 名、§4 片段、现有 `htop neofetch` 行与 `USER ubuntu`；产出两份文件 `USER` 之前的 apt `RUN` 含上述 12 个名字。

- [x] **Step 1:** 活动 Dockerfile 诊断 CLI 注释 + 12 个 apt 名
- [x] **Step 2:** 备选 Dockerfile digest「不在」列表、同一注释、同一组 apt 名
- [x] **Step 3:** 包名与 `USER ubuntu` 位置

```bash
set -euo pipefail
need='tree iftop iotop screen ncdu traceroute nmap ngrep conntrack psmisc fping dmidecode'
for f in .cursor/Dockerfile .cursor/Dockerfile.luckfox_pico; do
  for p in $need; do
    grep -E "^[[:space:]]+.*\b${p}\b" "$f" >/dev/null
  done
  test "$(awk 'NF{n=$0} END{print n}' "$f")" = 'USER ubuntu'
done
echo 'dockerfiles: packages present, USER ubuntu last'
```

Expected: 退出 0；打印 `dockerfiles: packages present, USER ubuntu last`。注释里可以出现 `conntrack-tools`，`apt-get install` 续行不能出现。实测见「最终验证证据」。

- [x] **Step 4:** 实现提交（仅两份 Dockerfile）

### Task 2: 2026-08-30 spec §2.3.1（已完成）

**Files:**

- Modify: `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`（§2.3.1 需求集合与备选写入列表）

**Interfaces:** 消费 Spec F4 / §2.4；产出需求集合与备选写入列表含 12 个 apt 名；`AGENTS.md` 仍不列包名。不改 07-13 spec §10。

- [x] **Step 1:** 需求集合补上 12 个排查 CLI；`which` 禁写句后禁止 `conntrack-tools` / `conntrackd` / `iotop-c`
- [x] **Step 2:** 备选「只补 FROM 没有的…」列表同时列出这 12 个 apt 名
- [x] **Step 3:** 2026-08-30 上述改动与 2026-09-16 spec/plan 同一 `docs(superpowers)` 提交，且在 feat 之后

### Task 3: V3 / V4（已完成）

**Files:** 只读检查 Task 1–2 产物。

**Interfaces:** 消费 Task 1–2；产出 V3/V4 通过。实测值见「最终验证证据」。

- [x] **Step 1: V3 分层**（`environment.json` / `install.sh` / `start.sh` / `AGENTS.md` 相对 `origin/dev` 无 diff；两份 Dockerfile 末指令 `USER ubuntu`）
- [x] **Step 2: V4 禁止包名**（SDK/工具 `RUN apt-get install` 续行 token 不含 `conntrack-tools` / `conntrackd` / `iotop-c` / `which` / `gnu-which`）

### Task 4: draft Environment Build 与 V1 / V2 / V5（已完成）

**Files:** 无仓库改动。Build 必须包含 Task 1 已推送的 Dockerfile。

**Interfaces:** 消费已 push 的 `cursor/dockerfile-user-ubuntu-1fe9`；产出 `SUCCEEDED` 的 draft `buildId` 与冷启动 V1/V2。

- [x] **Step 1: 触发 draft Build**（`trigger-environment-build`，`refs.repoUrl=github.com/yuangezhizao/luckfox-pico`，`refs.ref=cursor/dockerfile-user-ubuntu-1fe9`，不传 `environmentJson`）
- [x] **Step 2: 冷启动 V1 / V2**

```bash
set -euo pipefail
dpkg-query -W -f='${Package} ${Status}\n' \
  tree iftop iotop screen ncdu traceroute nmap ngrep conntrack psmisc fping dmidecode
for c in tree iftop iotop screen ncdu traceroute nmap ngrep conntrack pstree fping dmidecode; do
  command -v "$c" >/dev/null
done
echo v1v2_ok
```

Expected: 12 行均为 `install ok installed`；`command -v` 全部成功；打印 `v1v2_ok`。不要求无 sudo 的 `iftop` 出图，也不要求 `dmidecode` 读到 SMBIOS。必须在该 draft Build 冷启动上执行。典型失败：apt 清单写成 `conntrack-tools` → 退出 100。

- [x] **Step 3: 回填**（Build ID、命令与输出写入「最终验证证据」；文档仍为一个 commit）

---

## Execution Handoff

无剩余施工。Task 1–4 均已完成。V1/V2 须绑定 snapshot 已含当前 Dockerfile 的 draft Build。

## 完成情况总结

| 交付物 | 状态 |
| --- | --- |
| Task 1 两份 Dockerfile SDK/工具 `RUN` 12 个诊断 CLI | ✅ |
| Task 2 08-30 spec §2.3.1 需求集合与备选写入列表 | ✅ |
| Task 3 V3 / V4 | ✅ |
| Task 4 draft Build V1 / V2 / V5 | ✅ |
| spec + plan | ✅ |

**整体结论：** 活动与备选 Dockerfile 的 SDK/工具 `RUN` 均含 12 个 Ubuntu apt 名；`USER ubuntu` 仍为末指令。draft Build `bld-20260916-fd8cf69a-d6ed-453f-9826-272e104fd5e1` 冷启动 V1/V2 通过。规格已实施。

---

## 当前 Agent 基线（active Build，实现前）

会话 [`bc-b4e365ab-0472-45db-9c63-4ec14abb1a4b`](https://cursor.com/agents/bc-b4e365ab-0472-45db-9c63-4ec14abb1a4b)，snapshot [`bld-20260916-cac6cb9d-2b58-45e1-86f5-e19da08d54aa`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260916-cac6cb9d-2b58-45e1-86f5-e19da08d54aa)（`gitSetup=reuse_then_checkout`，`warmFork=cold`）。OS `Ubuntu 24.04.4 LTS`，`whoami=ubuntu`，`HOME=/home/ubuntu`。该快照的 Dockerfile 尚未写入本规格 12 个 apt 名。

```bash
set -euo pipefail
. /etc/os-release; printf '%s\n' "$PRETTY_NAME"
whoami
printf 'HOME=%s\n' "$HOME"
dpkg-query -W -f='${Package}\t${Status}\t${Version}\n' \
  tree iftop iotop screen ncdu traceroute nmap ngrep conntrack psmisc fping dmidecode || true
for c in tree iftop iotop screen ncdu traceroute nmap ngrep conntrack pstree fuser killall fping dmidecode; do
  printf '%-12s ' "$c"
  command -v "$c" || echo ABSENT
done
apt-cache policy tree iftop iotop screen ncdu traceroute nmap ngrep conntrack psmisc fping dmidecode
sha256sum /usr/local/share/vnc-desktop.Aptfile
grep -E '^(tree|iftop|iotop|screen|ncdu|traceroute|nmap|ngrep|conntrack|psmisc|fping|dmidecode)$' \
  /usr/local/share/vnc-desktop.Aptfile || true
```

| apt 包 | `dpkg-query -W` | Installed | Candidate（noble） | 验收命令 | `command -v` |
| --- | --- | --- | --- | --- | --- |
| tree | no packages found matching | (none) | 2.1.1-2ubuntu3.24.04.2 | tree | ABSENT |
| iftop | no packages found matching | (none) | 1.0~pre4-9build2 | iftop | ABSENT |
| iotop | no packages found matching | (none) | 0.6-42-ga14256a-0.2build1 | iotop | ABSENT |
| screen | no packages found matching | (none) | 4.9.1-1ubuntu1 | screen | ABSENT |
| ncdu | no packages found matching | (none) | 1.19-0.1 | ncdu | ABSENT |
| traceroute | no packages found matching | (none) | 1:2.1.5-1 | traceroute | ABSENT |
| nmap | no packages found matching | (none) | 7.94+git20230807.3be01efb1+dfsg-3build2 | nmap | ABSENT |
| ngrep | no packages found matching | (none) | 1.47+ds1-5build2 | ngrep | ABSENT |
| conntrack | no packages found matching | (none) | 1:1.4.8-1ubuntu1 | conntrack | ABSENT |
| psmisc | unknown ok not-installed | (none) | 23.7-1build1 | pstree | ABSENT（`fuser`/`killall` 同） |
| fping | no packages found matching | (none) | 5.1-1 | fping | ABSENT |
| dmidecode | no packages found matching | (none) | 3.5-3ubuntu0.1 | dmidecode | ABSENT |

`/usr/local/share/vnc-desktop.Aptfile` sha256 `819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8`：含 `procps`，不含上表 12 个名字。实现前活动 Dockerfile SDK/工具 `RUN` 仅有 `htop neofetch`。

结论：该 active 快照 **未安装**这 12 个包，对应命令均不在 `PATH`。noble 仓库 12 个均有 Candidate。不得因 Aptfile 未列出而从 Dockerfile 省略（写入集合只看 FROM dpkg，见 08-30 §2.3.1）。本表不能替代 Task 4 在含本 Dockerfile 的 draft Build 上的 V1/V2。

---

## 最终验证证据

通过标准见 Spec §5。未记录任何 Secret 内容。

| 项 | 命令 / 来源 | 结果 |
| --- | --- | --- |
| Dockerfile 清单 | Task 1 Step 3 循环：`grep` 12 名 + 末指令 `USER ubuntu` | `.cursor/Dockerfile` L56–57 与 `.cursor/Dockerfile.luckfox_pico` L43–44 均为 12/12；禁止名仅在注释；末指令 `USER ubuntu`。打印 `dockerfiles: packages present, USER ubuntu last`，退出码 0 |
| V3 | `git diff origin/dev -- .cursor/environment.json .cursor/install.sh .cursor/start.sh AGENTS.md`；两份 Dockerfile `awk 'NF{n=$0} END{print n}'` | diff 无输出；最后非空指令均为 `USER ubuntu` |
| V4 | 对两份 Dockerfile 扫描以 `RUN apt-get` 且含 `install` 开头的块，token 不得为 `conntrack-tools` / `conntrackd` / `iotop-c` / `which` / `gnu-which`（注释行跳过） | 打印 `v4 ok`，退出码 0 |
| V5 | `cursor-cloud` `trigger-environment-build`（`refs.repoUrl=github.com/yuangezhizao/luckfox-pico`，`refs.ref=cursor/dockerfile-user-ubuntu-1fe9`，不传 `environmentJson`）后 `list-environment-builds` | `buildId=bld-20260916-fd8cf69a-d6ed-453f-9826-272e104fd5e1`，`status=SUCCEEDED`，`isDraft=true`，`createdAtMs=1789564424682`，`completedAtMs=1789565085545`（约 662s）。Dashboard：https://cursor.com/dashboard/cloud-agents/builds/bld-20260916-fd8cf69a-d6ed-453f-9826-272e104fd5e1 。构建日志 `[BUILD] Unpacking`：`tree` 2.1.1-2ubuntu3.24.04.2、`iftop` 1.0~pre4-9build2、`iotop` 0.6-42-ga14256a-0.2build1、`screen` 4.9.1-1ubuntu1、`ncdu` 1.19-0.1、`traceroute` 1:2.1.5-1、`nmap` 7.94+git20230807.3be01efb1+dfsg-3build2、`ngrep` 1.47+ds1-5build2、`conntrack` 1:1.4.8-1ubuntu1、`psmisc` 23.7-1build1、`fping` 5.1-1、`dmidecode` 3.5-3ubuntu0.1；无 `Unable to locate package` / `conntrack-tools` |
| V1 | 该 draft Build 冷启动上 Task 4 Step 2 的 `dpkg-query -W` | 12 行均为 `install ok installed`：`conntrack` `dmidecode` `fping` `iftop` `iotop` `ncdu` `ngrep` `nmap` `psmisc` `screen` `traceroute` `tree`。OS `Ubuntu 24.04.4 LTS`，`whoami=ubuntu`，`HOME=/home/ubuntu`，`environment-info.build.buildId=bld-20260916-fd8cf69a-d6ed-453f-9826-272e104fd5e1` |
| V2 | 同上冷启动：`command -v` 于 `tree iftop iotop screen ncdu traceroute nmap ngrep conntrack pstree fping dmidecode` | 12 个命令均成功；打印 `v1v2_ok`，退出码 0 |
