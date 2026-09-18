# Luckfox Pico Cloud Agent 平台安装与启动顺序实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Cursor 平台 Environment Build / Agent Run 命令层与 `/opt/cursor/` 树写成活目录，并在 08-30 spec §2.3、08-30 plan 流水引言、07-13 §10 加指针。

**Architecture:** 活目录只在 2026-09-18 spec。08-30 plan「Environment Build install 流水」保持 2026-09-06 历史时间表，不覆盖数字。合入只加指针，不把命令表或 Aptfile 清单抄进旧文档。不改 Dockerfile、`AGENTS.md`、`environment.json`、`install.sh`、`start.sh`。

**Tech Stack:** superpowers 文档；Cursor Environment Build 日志命令名；容器内 `/opt/cursor/` 与 `/usr/local/share/vnc-desktop.Aptfile`。

**Spec:** [`docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md`](../specs/2026-09-18-luckfox-cloudagent-platform-install-design.md)

## Global Constraints

- 使用现有分支 `cursor/platform-install-spec-8f0d`，PR base 为 `dev`；直接使用当前工作树，不创建 worktree。
- 相对 `origin/dev`：第一提交已含 09-18 spec 初稿；本 plan 与 spec Review 修订、三处指针为**单个** `docs(superpowers)` 提交。
- 仅修改 `docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md`、本 plan、`docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` 的 §2.3 平台 Aptfile 行、`docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md` 的「Environment Build install 流水」引言、`docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` 的 §10 交付物表。不改 `.cursor/Dockerfile*`、`AGENTS.md`、`environment.json`、`install.sh`、`start.sh`、`./build.sh`、板上固件。
- 不改写 08-30 plan 流水表中的 2026-09-06 UTC、秒数、包数、磁盘增量、Chrome `152.0.7977.82`。
- 不把 Aptfile 58 包或 Build 命令全表抄进 07-13 / 08-30 spec。
- 控制器注入命令只记命令名与可见产物，不编造 `podConfig.ts` 脚本正文。
- Cursor Secrets、token、私钥、签名公钥不得进入 git、日志、plan 或提交信息。
- 不要求 draft Environment Build，也不跑 `./build.sh allsave`。
- 执行 plan 时只允许在「最终验证证据」中回填可复现命令与实测值。已完成 Task 只保留步骤与文件目录。`git cz` 主题为 `type(scope): <gitmoji> subject`；body 用 `- ` 并列 why，末尾只留一个 `详见 spec §X` 指针。
- 所有多命令验证块以 `set -euo pipefail` 开头。

---

## File Structure

| 文件 | 责任 |
| --- | --- |
| `docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md` | 活目录：Build/Run 命令层、`/opt/cursor/` 树、Aptfile、grilling QA |
| `docs/superpowers/plans/2026-09-18-luckfox-cloudagent-platform-install.md` | 本文件：Task、完成情况、最终验证证据 |
| `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` | §2.3 平台 Aptfile 行加指向 09-18 spec 的指针 |
| `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md` | 「Environment Build install 流水」引言加指针；表内 09-06 数字不动 |
| `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` | §10 交付物表加一行指针 |

### Task 1: spec 状态与 `/opt/cursor/` 树

**Files:**

- Modify: `docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md`（状态、§3.4、V1、§9）

**Interfaces:** 消费 Review 结论与 `tree /opt/cursor`；产出状态「已 Review」，§3.4 含树与各节点用途，关联计划指向本文件。

- [x] **Step 1:** 状态改为已 Review；关联计划指向本文件
- [x] **Step 2:** §3.4 写入 `tree /opt/cursor` 与路径用途表（含运行时副本）；点目录 `.exec-daemon` 只作一句说明，不展开正文
- [x] **Step 3:** V1 改为「已 Review、关联计划已写成正文」；§9 指向本 plan

### Task 2: 08-30 spec §2.3 指针

**Files:**

- Modify: `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md`（§2.3 表「平台 Aptfile」行）

**Interfaces:** 消费 Spec F4 / §2.1；产出该行末尾指向 09-18 spec；仍保留 plan 流水表指针。

- [x] **Step 1:** 在「完整包数、耗时与命令时间表见 plan「Environment Build install 流水」」之后追加：现行命令层与 `/opt/cursor/` 树见 [`2026-09-18` spec](2026-09-18-luckfox-cloudagent-platform-install-design.md)。

目标单元格（只改这一句，不改表其它行）：

```
| **平台 Aptfile** | Cursor 在 Environment Build 中、Dockerfile 之后按 `/usr/local/share/vnc-desktop.Aptfile` 安装 TigerVNC / XFCE / Chrome / 字体等；不写入本仓 Dockerfile。完整包数、耗时与命令时间表见 plan「Environment Build install 流水」。现行命令层与 `/opt/cursor/` 树见 [`2026-09-18` spec](2026-09-18-luckfox-cloudagent-platform-install-design.md) |
```

### Task 3: 08-30 plan 流水引言指针

**Files:**

- Modify: `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md`（`## Environment Build install 流水` 后第一段）

**Interfaces:** 消费 Spec F1 / F4 / §2.5；产出引言指向 09-18 spec 并声明本表冻结；表内 UTC/秒数/包数/Chrome 152 行不动。

- [x] **Step 1:** 在「来源 draft Build」之前插入一句：现行 Environment Build / Agent Run 命令层见 [`2026-09-18-luckfox-cloudagent-platform-install-design.md`](../specs/2026-09-18-luckfox-cloudagent-platform-install-design.md)。本表冻结为 2026-09-06 该次 Build 的墙钟与磁盘增量，不随后来 Build 改写。

### Task 4: 07-13 §10 指针

**Files:**

- Modify: `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md`（§10 交付物表）

**Interfaces:** 消费 Spec F4 / §2.1；产出新行指向 09-18 spec，不枚举 Aptfile 包名或命令全表。

- [x] **Step 1:** 在 `.cursor/Dockerfile.luckfox_pico` 行与 `AGENTS.md` 行之间插入：

```
| 平台自动安装（Cursor） | 不写入本仓 | 命令层、Aptfile、`/opt/cursor/` 树见 [`2026-09-18-luckfox-cloudagent-platform-install-design.md`](2026-09-18-luckfox-cloudagent-platform-install-design.md)；08-30 plan「Environment Build install 流水」为 2026-09-06 历史时间表 |
```

### Task 5: V2 / V3 / V5

**Files:** 只读检查 Task 1–4 产物。

**Interfaces:** 消费 Task 1–4；产出 V2/V3/V5 通过。实测值见「最终验证证据」。

- [x] **Step 1: V2**（`.cursor/Dockerfile*` / `AGENTS.md` / `environment.json` / `install.sh` / `start.sh` 相对 `origin/dev` 无 diff）
- [x] **Step 2: V3**（Aptfile sha256 与 58 名与 spec §4 一致；`tree /opt/cursor` 与 spec §3.4 树一致）
- [x] **Step 3: V5**（三处指针指向 09-18 spec；08-30 plan 流水表仍含 `bld-20260906-a344b2e4` 与 Chrome `152.0.7977.82`）
- [x] **Step 4:** 文档单个提交并推送，开草稿 PR（base `dev`）

## 最终验证证据

命令与输出见本提交当时工作树。

V2：`git diff origin/dev -- .cursor/Dockerfile .cursor/Dockerfile.luckfox_pico .cursor/environment.json .cursor/install.sh .cursor/start.sh AGENTS.md` 为空。

V3：`sha256sum /usr/local/share/vnc-desktop.Aptfile` 为 `819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8`；`grep -vE '^#|^$'` 包名 58 个；`tree /opt/cursor` 为 10 directories、18 files，与 spec §3.4 树一致。

V5：08-30 spec §2.3 平台 Aptfile 行含 `2026-09-18-luckfox-cloudagent-platform-install-design.md`；08-30 plan 流水引言含同一文件相对路径，且正文仍有 `bld-20260906-a344b2e4-98f2-411d-86fa-d45b6dfa20cb` 与 `152.0.7977.82`；07-13 §10 含「平台自动安装（Cursor）」行。
