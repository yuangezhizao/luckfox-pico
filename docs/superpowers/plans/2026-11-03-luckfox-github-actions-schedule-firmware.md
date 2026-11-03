# Luckfox Pico CI 月度重建镜像后编译固件实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 删除 `build-firmware` 的 schedule 门禁，使月度重建的镜像当月即编译 3 组合固件；run 摘要写入镜像 digest；旧 CI spec/plan 加修订注记；验证手动获取方法。

**Architecture:** 只改 `.github/workflows/build-luckfox-pico-firmware.yml`（删 1 行 `if`、改注释、构建步骤写 run 摘要），其余为文档。

**Tech Stack:** GitHub Actions、`gh` CLI、`actionlint` 1.7.7（含 shellcheck）。

**状态：** 已实施；本地静态检查、本分支 dispatch 与 `dev` 上的手动方法均已验证，手动 run 的固件结果贴 PR #12 评论（Ultra W 因 runner 磁盘不足失败，与本 PR 无关，见 spec §7.1）。

**Spec:** [`docs/superpowers/specs/2026-11-03-luckfox-github-actions-schedule-firmware-design.md`](../specs/2026-11-03-luckfox-github-actions-schedule-firmware-design.md)

## 1. Global Constraints

- 分支 `pi/ci-schedule-firmware`，PR #12，base 为 `dev`。
- 提交按 `luckfox_pico_lvgl_example` `AGENTS.md`「提交约定」；spec 与 plan 放在 PR 最后一个提交；rebase 保留 author time。
- 不在 feature 分支 `force_rebuild`（会覆盖共享 tag，spec §6）。
- 不改 `.gitignore`、`AGENTS.md`、`.cursor/`。

## 2. File Structure

| 文件 | 责任 |
| --- | --- |
| `.github/workflows/build-luckfox-pico-firmware.yml` | 删除 schedule 门禁；写 run 摘要 |
| `docs/superpowers/specs/2026-07-17-luckfox-github-actions-ci-design.md` | 头部「后续修订」行与 5 处〔2026-11-03 修订〕注记 |
| `docs/superpowers/plans/2026-07-17-luckfox-github-actions-ci.md` | 2 处〔2026-11-03 修订〕注记，YAML 快照不改 |

## 3. Tasks

### Task 1：workflow 改动（已完成）

- [x] **Step 1:** 删除 `build-firmware` 的 `if: github.event_name != 'schedule'`，更新其上方注释与 `schedule` cron 注释
- [x] **Step 2:** 构建步骤 `env` 增加 `EVENT_NAME`、`REF_NAME`；三条路径各设 `SOURCE`；写 `$GITHUB_OUTPUT` 之后追加摘要表格
- [x] **Step 3:** 静态检查与摘要片段试跑；在本分支 dispatch（不勾 `force_rebuild`）执行新代码，build-image 通过后取消固件 job（结果见 §4）
- [x] **Step 4:** 提交 `ci(github-actions): 👷 …`

### Task 2：旧 CI spec / plan 注记（已完成）

- [x] **Step 1:** CI spec 头部加「后续修订」行；F3、§4.2、§4.3、§7 R8、§9 Q11 原文保留，追加〔2026-11-03 修订〕
- [x] **Step 2:** CI plan 首段「触发」与「镜像重建机制」的 build-firmware 条目追加注记
- [x] **Step 3:** 提交 `docs(superpowers): 📝 …`

### Task 3：验证手动方法（已完成）

- [x] **Step 1:** 在 `dev` 上 `gh workflow run … -f force_rebuild=false`
- [x] **Step 2:** `build-image` 走复用路径、provenance 验证通过、digest 等于 11-01 schedule 的 digest（证据见 §4）；固件结果贴 PR #12 评论：两个 Pico Max 组合成功，Ultra W 磁盘耗尽失败（spec §7.1）

## 4. 最终验证证据

```bash
set -euo pipefail
W=.github/workflows/build-luckfox-pico-firmware.yml
curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz | tar xz -C /tmp actionlint
/tmp/actionlint "$W"
! grep -n "github.event_name != 'schedule'" "$W"
test "$(grep -c 'SOURCE=' "$W")" -eq 3
test "$(grep -c '2026-11-03' docs/superpowers/specs/2026-07-17-luckfox-github-actions-ci-design.md)" -ge 6
test "$(grep -c '2026-11-03' docs/superpowers/plans/2026-07-17-luckfox-github-actions-ci.md)" -eq 2
echo ok
```

| 项 | 来源 | 结果 |
| --- | --- | --- |
| 上面的检查 | 本地 | 打印 `ok`；`actionlint` 对改前的 workflow 同样退出 0 |
| 摘要片段 | 本地用假变量执行写摘要的 shell 片段 | 输出 `### 🐳 CI 镜像` 与 4 行表格 |
| 本分支 dispatch | run 41618683915，job 125858502463 | build-image 成功，日志出现 `SOURCE="复用（provenance 验证通过）"`，digest 同下；写摘要所在步骤在 `set -euo pipefail` 下成功结束，作者登录后在 run 页面确认「🐳 CI 镜像」表格显示正常；固件 job 已取消 |
| 手动方法 build-image | run 41614992877，job 125846110968 | 复用 tag `60864362d31a9efa3cf886acd8a5ecdb`；`buildSignerURI` …`@refs/heads/dev`，`sourceRepositoryRef` `refs/heads/dev`；digest `sha256:a470b047657e08d806889b67825436935287427ac370244a5343929bb4b865f7`（与 schedule run 41266391514 相同） |
