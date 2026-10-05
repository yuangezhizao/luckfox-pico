# Luckfox Pico Cloud Agent 平台安装与启动顺序实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 写出平台安装与启动分层规格，并让既有文档、`AGENTS.md` 和 Dockerfile 注释与之保持一致。

**Architecture:** 规格只讲本仓配置与 Cursor 平台的衔接；平台 18 个安装步骤和 Aptfile 原文引用 Cursor-Cloud-Agents 固定提交 `db82179`，核验脚本也直接读取该提交。既有文档只加指针或更正个别说法。所有改动都是文档和注释，不改构建指令与脚本。

**Tech Stack:** Markdown；Cursor Environment Build 日志；Cursor-Cloud-Agents 文件级存档；当前 Agent 上的 `/opt/cursor/`、dpkg 与进程表。

**Spec:** [`docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md`](../specs/2026-09-18-luckfox-cloudagent-platform-install-design.md)

---

## Global Constraints

- 在现有分支 `cursor/platform-install-spec-8f0d` 上工作，不另建 worktree；PR #11 目标分支为 `dev`，状态为 Ready for review。
- 相对 `dev` 保持两个提交：第一个更正既有文档与注释（7 个文件），第二个新增本规格和本计划。第一个提交中的链接指向第二个提交才加入的规格，以最终 PR 树验收。
- 不改 Dockerfile 构建指令、`environment.json`、`install.sh`、`start.sh`、`./build.sh` 和板上固件；不跑 `./build.sh`，不触发 Environment Build。
- 08-30 plan 中 09-06 时间表的数字不动。
- 不在本仓重新列出平台 18 步和 Aptfile 全文；两份 Dockerfile 原有的包名注释保留。
- 平台控制器直接下发的步骤只记命令名和可见产物，不推测脚本内容。
- 凭据和 Build 日志原文不进入仓库、提交信息或 PR。进程参数中含有 token，核验时只读取进程名、属主和父进程。
- 提交作者与提交者均为 `Cursor Agent <cursoragent@cursor.com>`，使用 SSH 签名，消息遵循 cz-conventional-emoji。改写历史前先备份分支，推送时使用显式 `--force-with-lease`。

---

## File Structure

| 文件 | 改动 | 所在提交 |
| --- | --- | --- |
| `docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md` | 新增：平台安装与启动分层规格 | 2 |
| `docs/superpowers/plans/2026-09-18-luckfox-cloudagent-platform-install.md` | 新增：本计划 | 2 |
| `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` | §2.2 更正镜像构建时机；§10 交付物表加一行指针 | 1 |
| `docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md` | §2.3 加指针，并更正 Chrome 的安装来源 | 1 |
| `docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md` | 「Environment Build install 流水」首段加指针 | 1 |
| `docs/superpowers/specs/2026-09-14-luckfox-cloudagent-default-user-design.md` | §2.4 tini 的作用 | 1 |
| `AGENTS.md` | 桌面包安装时机一句 | 1 |
| `.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico` | 顶部平台注释 | 1 |

---

### Task 1: 编写规格（已完成）

**Files:** Create `docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md`

- [x] **Step 1:** 对照 10-03 Build 日志和存档 §4.0.3 写 §2 Build 流程；平台 18 步只引用，不复制
- [x] **Step 2:** 在当前 Agent 上核对进程、挂载和 `/opt/cursor/`，写 §3、§4
- [x] **Step 3:** 写 §5 软件包来源，Aptfile 原文引用存档
- [x] **Step 4:** 写设计决策、已知边界、常见误读、验收标准和 QA 记录；状态改为已 Review

### Task 2: 既有规格与计划：加指针并更正说法（已完成）

**Files:** Modify 07-13 spec §2.2 与 §10、08-30 spec §2.3、08-30 plan「Environment Build install 流水」首段

- [x] **Step 1:** 07-13 §10：在 `.cursor/Dockerfile.luckfox_pico` 行与 `AGENTS.md` 行之间加「平台自动安装（Cursor）」行；§2.2 把"每次启动时从 Dockerfile 构建镜像"改为在 Environment Build 时构建、Agent 从快照启动
- [x] **Step 2:** 08-30 spec §2.3：「平台 Aptfile」行末尾加指针；该行、装配顺序和流程图中"Chrome 按 Aptfile 安装"的说法改为 Chrome 另行安装
- [x] **Step 3:** 08-30 plan：首段开头加指针，说明下表是 09-06 的历史记录；原有句子与表格不动

### Task 3: 更正 AGENTS.md、Dockerfile 注释与 09-14 规格（已完成）

**Files:** Modify `AGENTS.md`、`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`、09-14 spec §2.4

- [x] **Step 1:** `AGENTS.md`：改写桌面包那一句，区分 Build 装包与 Run 启动，不加链接
- [x] **Step 2:** 两份 Dockerfile：同步改写顶部平台注释；复核 Aptfile 后把日期更新为 2026-10-05，备选文件注明未重新构建；不碰非注释行
- [x] **Step 3:** 09-14 spec §2.4：tini 的作用改为「启动并管理子进程 pod-daemon」

### Task 4: 验收 V1–V5（已完成）

在 luckfox-pico 仓库根目录执行。先设置两个变量：`LOG` 指向 10-03 Build 日志，`ARCHIVE` 指向包含 `db82179` 的 Cursor-Cloud-Agents 本地克隆。存档内容一律用 `git show` 从固定提交读取，不受该克隆当前所在分支的影响。

- [x] **Step 1: V1、V2、V5（仓库内文件）**

```bash
set -euo pipefail
spec=docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md
plan=docs/superpowers/plans/2026-09-18-luckfox-cloudagent-platform-install.md

# V1：规格已 Review，关联计划存在
grep -qxF -- '- **状态**：已 Review' "$spec"
grep -qF "(../plans/$(basename "$plan"))" "$spec"
test -s "$plan"
echo v1-ok

# V2：Dockerfile 只改注释；AGENTS.md 只改一行且不加链接；配置与脚本不变
git diff --quiet origin/dev -- .cursor/environment.json .cursor/install.sh .cursor/start.sh
for f in .cursor/Dockerfile .cursor/Dockerfile.luckfox_pico; do
  diff <(git show "origin/dev:$f" | grep -vE '^[[:space:]]*(#|$)') <(grep -vE '^[[:space:]]*(#|$)' "$f")
done
test "$(git diff --numstat origin/dev -- AGENTS.md | cut -f1-2)" = "$(printf '1\t1')"
if git diff origin/dev -- AGENTS.md | grep -q "^+.*$(basename "$spec")"; then exit 1; fi
echo v2-ok

# V5：三处指针；08-30 plan 原句完整保留；09-14 spec 只改 tini 一行
for f in docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md \
         docs/superpowers/specs/2026-08-30-luckfox-cloudagent-tailscale-design.md \
         docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md; do
  grep -qF "$(basename "$spec")" "$f"
done
python3 - <<'PY'
import subprocess

def changed(path):
    old = subprocess.check_output(["git", "show", f"origin/dev:{path}"], text=True).splitlines()
    new = open(path, encoding="utf-8").read().splitlines()
    assert len(old) == len(new), path
    return [(a, b) for a, b in zip(old, new) if a != b]

(old, new), = changed("docs/superpowers/plans/2026-08-30-luckfox-cloudagent-tailscale.md")
assert new.endswith(old)
(old, new), = changed("docs/superpowers/specs/2026-09-14-luckfox-cloudagent-default-user-design.md")
assert new.startswith("| `tini`（PID 1） |")
PY
echo v5-ok
```

Expected: 依次打印 `v1-ok`、`v2-ok`、`v5-ok`。

- [x] **Step 2: V3、V4（日志、存档与当前 Agent）**

```bash
set -euo pipefail
: "${LOG:?设置为 environment-build-logs-bld-20261003.txt 的路径}"
: "${ARCHIVE:?设置为 Cursor-Cloud-Agents 本地克隆的路径}"
python3 - "$ARCHIVE" "$LOG" <<'PY'
from pathlib import Path
import hashlib
import os
import pwd
import re
import subprocess
import sys

archive, log_path = sys.argv[1:]
ref = "db8217941c3f4d017a0ec5098e7603d402aefeb3"
spec = Path("docs/superpowers/specs/2026-09-18-luckfox-cloudagent-platform-install-design.md").read_text(encoding="utf-8")

def stored(path):
    return subprocess.check_output(["git", "-C", archive, "show", f"{ref}:{path}"])

# V3：Aptfile 与存档一致，58 个包名与两份 Dockerfile 注释相同
apt = Path("/usr/local/share/vnc-desktop.Aptfile").read_bytes()
assert apt == stored("usr/local/share/vnc-desktop.Aptfile")
assert hashlib.sha256(apt).hexdigest() == "819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8"
names = {s.strip() for s in apt.decode().splitlines() if s.strip() and not s.lstrip().startswith("#")}
assert len(names) == 58
for path in (".cursor/Dockerfile", ".cursor/Dockerfile.luckfox_pico"):
    listed = set()
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("# │   ") and ":" in line and "浏览器" not in line:
            listed.update(line.split(":", 1)[1].split())
    assert listed == names, path
print("v3-ok")

# V4（Build）：18 步顺序取自存档 §4.0.3，与本地日志逐项比较
section = stored("docs/superpowers/specs/2026-10-04-cloudagent-env-snapshot-design.md").decode()
section = section.split("#### 4.0.3 ", 1)[1].split("\n### 4.1 ", 1)[0]
rows = re.findall(r"^\| (\d+) \| `([a-z-]+)` \|", section, re.M)
assert [int(n) for n, _ in rows] == list(range(1, 19))
data = Path(log_path).read_bytes()
assert hashlib.sha256(data).hexdigest() == "b6cf5002747f0302a55a2499c498bbbeec0d37ca24a883a46e42eda49e9514e4"
log = data.decode()
assert "bld-20261003-4581ee1c-6629-4038-965b-04fde88b37a1" in log
assert re.findall(r"\[INSTALL\] Command: ([a-z-]+)", log) == [name for _, name in rows]
assert re.findall(r"\[INSTALL\] Exit code: (\d+)", log) == ["0"] * 20
for name in ("core-dumps", "desktop-init", "exec-daemon"):
    assert f"Started detached setup start command: start:{name}" in log
assert "ssh-keygen: generating new host keys" in log
lines = log.splitlines()
for no, marker in [(49, "build cache hit"), (51, "build cache hit"),
                   (112, "Command: install-exec-daemon"), (3161, "Command: install-agent-store-fuse"),
                   (159, "6 upgraded, 0 newly installed"), (543, "15 upgraded, 406 newly installed"),
                   (2935, "0 upgraded, 0 newly installed"), (2954, "0 upgraded, 1 newly installed"),
                   (2985, "google-chrome-stable (154.0.8037.97-1)"), (3250, "2 upgraded, 42 newly installed"),
                   (3641, "Snapshot ready"), (3642, "Warming skipped")]:
    assert marker in lines[no - 1], no
print("v4-ok")

# V4（Run）：当前 Agent 的磁盘与存档一致，进程、挂载、链接和目录树与规格一致
for f in ("exec-daemon/exec_daemon_version", "usr/local/bin/cursor_agent_store_fuse_version",
          "opt/cursor/cloud-agent-tools/current.bundle-hash", "usr/local/share/vnc-desktop.Aptfile",
          "usr/local/share/desktop-init.sh"):
    assert Path("/" + f).read_bytes() == stored(f), f

procs = {}
for d in os.listdir("/proc"):
    if not d.isdigit():
        continue
    try:
        status = dict(l.split(":", 1) for l in Path(f"/proc/{d}/status").read_text().splitlines() if ":" in l)
        args = Path(f"/proc/{d}/cmdline").read_bytes().split(b"\0")
        user = pwd.getpwuid(int(status["Uid"].split()[0])).pw_name
    except (OSError, KeyError):
        continue
    procs[int(d)] = (status["Name"].strip(), args, int(status["PPid"]), user)

def has(pred):
    return any(pred(*p) for p in procs.values())

assert procs[1][0] == "tini" and procs[1][3] == "root"
pods = [pid for pid, (n, _, pp, u) in procs.items() if n == "pod-daemon" and pp == 1 and u == "root"]
assert len(pods) == 1
pod = pods[0]
assert has(lambda n, a, pp, u: b"/exec-daemon/index.js" in a and pp == pod and u == "ubuntu")
assert has(lambda n, a, pp, u: a[0] == b"/usr/local/bin/cursor-agent-store-fuse" and pp == pod and u == "ubuntu")
assert has(lambda n, a, pp, u: b"/usr/local/share/desktop-init.sh" in a and pp == 1 and u == "ubuntu")
for name in ("tailscaled", "sshd"):
    assert has(lambda n, a, pp, u, name=name: n == name and pp == 1 and u == "root"), name

fstype = subprocess.check_output(["findmnt", "-n", "-o", "FSTYPE", "-T", "/cursor/stores"], text=True)
assert fstype.strip() == "fuse.agent-store"
assert os.readlink("/opt/cursor/artifacts") == "/cursor/stores/self/artifacts"
assert Path("/tmp/cursor/start-user/start-user.status").read_text().strip() == "0"

block = spec.split("```text\n/opt/cursor\n", 1)[1].split("\n```", 1)[0]
expected, stack = {}, ["/opt/cursor"]
for line in block.splitlines():
    m = re.search(r"[├└]── ", line)
    depth = m.start() // 4 + 1
    name, *target = line[m.end():].split(" -> ", 1)
    stack[depth:] = [stack[depth - 1] + "/" + name]
    expected[stack[depth]] = target[0] if target else None
actual = {}
for top, dirs, files in os.walk("/opt/cursor"):
    dirs[:] = [d for d in dirs if not d.startswith(".")]
    for name in dirs + [f for f in files if not f.startswith(".")]:
        p = os.path.join(top, name)
        actual[p] = os.readlink(p) if os.path.islink(p) else None
assert actual == expected
print("run-ok")
PY
```

Expected: 依次打印 `v3-ok`、`v4-ok`、`run-ok`。期望的步骤顺序从存档 §4.0.3 读取，本计划不另存一份。日志共有 20 个成功的退出码：18 个平台命令、本仓 `install.sh`，以及 L102 一条不带 `Command:` 的记录。

### Task 5: 提交与 PR（已完成）

- [x] **Step 1:** 备份分支后重建两个提交：第一个包含 Task 2、Task 3 的 7 个文件，第二个包含规格与本计划
- [x] **Step 2:** 核对两个提交的作者、提交者和 SSH 签名，用 `--force-with-lease` 推送
- [x] **Step 3:** 更新 PR #11 的标题与正文，将状态切为 Ready for review

---

## 最终验证证据

2026-10-05 在当前 Agent 上执行 Task 4 的两段脚本，全部通过。

**Build 日志**：`environment-build-logs-bld-20261003.txt` 由用户提供，原文不入库。共 3661 行，sha256 `b6cf5002747f0302a55a2499c498bbbeec0d37ca24a883a46e42eda49e9514e4`。主要位置：

- L48–L51：Dockerfile 的 SDK 与 Tailscale 两层命中构建缓存
- L112–L3165：平台 18 个安装步骤，顺序与存档 §4.0.3 一致
- L3166–L3176：三个 `start:*` 以 detached 方式拉起
- L3641–L3642：`Snapshot ready`、`Warming skipped`

Cursor-Cloud-Agents 规格引用的是另一份 3365 行的日志副本，这里没有取得。两份日志的行号不能混用。

**各步骤的 apt 操作**：

| 步骤 | 日志行 | 升级 | 新装 |
| --- | --- | --- | --- |
| `install-cloud-agent-assets` 前置包 | L159 | 6 | 0 |
| `install-vnc-desktop-apt-packages` | L543 | 15 | 406 |
| `install-google-chrome` 前置包 | L2935 | 0 | 0 |
| `install-google-chrome` 浏览器 | L2954 | 0 | 1 |
| 本仓 `install.sh`（OpenSSH） | L3250 | 2 | 42 |

Chrome 版本为 `154.0.8037.97-1`（L2985）。这些是各步骤自己的 apt 操作数，相加也得不到环境的包总数。

**当前 Agent 与存档**：

- 从 `db82179` 读取的 `exec-daemon/exec_daemon_version`、`usr/local/bin/cursor_agent_store_fuse_version`、`opt/cursor/cloud-agent-tools/current.bundle-hash`、`usr/local/share/vnc-desktop.Aptfile`、`usr/local/share/desktop-init.sh`，与当前 Agent 上的同名文件逐字节一致。
- `/exec-daemon` 与 `/opt/cursor/.exec-daemon` 的创建时间为 10-03 17:36:58.402 和 17:38:30.054（+0800），分别落在 `install-exec-daemon` 与 `create-exec-daemon-dir` 的时间窗内。据此判断当前 Agent 的磁盘来自这次 Build。
- Aptfile sha256 `819987b7fef06af920bd9313347e05ca2fb0cd32ab4ad1e32a2a045238e4abb8`，58 个包名，与两份 Dockerfile 注释清单相同。
- `google-chrome-stable` 为 `154.0.8037.97-1`；工具包哈希为 `c06a0611e1e6a422d86412295478c5681504707a103c16b3b20ef457374da371`；`desktop-init.sh` 共 394 行，sha256 `4f8d5598ca29964beb4fa63587d204dda8f9a89a3700eb59a51f7961615df7ad`。
- `tree /opt/cursor` 输出 10 个目录、18 个文件，路径与链接目标和规格 §4 一致。
- 进程关系与规格 §3 一致；`/cursor/stores` 为 `fuse.agent-store`，`/opt/cursor/artifacts` 指向 `/cursor/stores/self/artifacts`，`start-user.status` 为 `0`。这些只说明挂载和链接存在，后端能否读写见规格 §7。

**仓库文件**：`.cursor/install.sh`、`.cursor/start.sh` 的 sha256 分别为 `0f21141c…a6877`、`2d14a2c5…bc37`，与 `dev` 相同；两份 Dockerfile 去掉注释与空行后与 `dev` 一致。
