# Luckfox Pico 外置内核模块 helloworld 例程实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `sysdrv/drv_ko/examples/helloworld/` 增加一个可移植、带前置检查和完整中文教程的外置 Linux 内核模块例程，并在 Luckfox Pico Ultra W 上完成构建、传输、加载和卸载验收。

**Architecture:** 例程由 `helloworld.c`、独立双阶段 Kbuild Makefile 和中文 README 组成，不接入父级 `M_DIRS`，也不进入 OEM 固件。Linux/amd64 Ubuntu 24.04 编译环境负责准备 Ultra W 内核输出并交叉编译模块；macOS 负责取得产物、核对哈希并通过 ADB 在开发板上验收。

**Tech Stack:** Linux 5.10.160 Kbuild、GNU Make、`arm-rockchip830-linux-uclibcgnueabihf` GCC 8.3.0、Ubuntu 24.04 linux/amd64、Docker、ADB、BusyBox。

**状态：** 已实施并通过验收。

**关联 spec：** [`docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md`](../specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md)

## Global Constraints

- 使用现有分支 `codex/helloworld-kernel-module-example`；该分支基于当前 `dev`，PR #7 的 base 为 `dev`。
- 不修改 `sysdrv/drv_ko/Makefile`、`M_DIRS`、Kconfig、defconfig、设备树、启动脚本或固件打包规则。
- 不把 `helloworld.ko` 复制到 `kernel_drv_ko`、`output/out/oem/usr/ko` 或开发板 `/oem/usr/ko`。
- 不创建 `release_*` 目录，不提交 `.ko`、`.o`、`.cmd`、`Module.symvers`、`modules.order` 等 Kbuild 产物。
- `helloworld.c` 和 Makefile 按 spec 使用 `GPL-2.0-only` SPDX；保留 `MODULE_LICENSE("GPL")`、`MODULE_AUTHOR("Luckfox")` 和 `MODULE_VERSION("V1.0")`。
- Linux 构建只接受 linux/amd64 Ubuntu 24.04；不使用 macOS 原生编译、开发板本机构建或现有官方 Ubuntu 22.04 `luckfox` 容器作为正式验收环境。
- 远程验证使用 `mastodon.yuangezhizao.cn`，SSH 端口只从 macOS 控制机未入库的 `LUCKFOX_SSH_PORT` 环境变量读取，不在文档或命令中记录具体值；远程 `/data/luckfox-pico` 直接切换到 `codex/helloworld-kernel-module-example`，不创建额外 worktree。
- 当前 `./build.sh kernel` 在 `O=sysdrv/source/objs_kernel` 模式下不会执行 `modules` 目标。必须随后显式执行内核 `make ... modules`，生成 `scripts/module.lds` 和最终 `Module.symvers`。
- 当前本地工作树存在与本例程无关的既有修改和 `.DS_Store`；所有暂存、检查和提交命令必须限定到本计划涉及的路径。
- 默认不区分大小写的 macOS APFS 无法完整表示仓库中的 21 对大小写冲突路径；日常 pull、rebase 与构建应使用区分大小写的 APFS 卷/磁盘映像或 Linux 文件系统，不能用 `core.ignorecase=false` 代替文件系统迁移，详见 spec §12 Q13。
- 执行时若发现需要修改上述范围之外的文件，立即停止并按“发现偏差：XXX，是否允许加入 plan？”汇报；获得允许并更新 plan 后才能继续。
- Task 1–5 已按获批计划执行并通过验收；PR Review 与合并由维护者负责。

---

## 最终验证证据

- 验收对象：本 PR 中的模块源码与 Makefile；linux/amd64 Ubuntu 24.04 镜像 `sha256:176845c9591d95293ba0cba8da38774cb9b453b2c5653bcd33e058a8ca9d2bee`，标准构建成功且未使用代理回退；默认完整路径与 PATH 裸前缀构建产物均为 `c3f48770f72f08980cd8f24bb296010f0c55060075bb00ca5f261704850fdb68`，并已针对该产物完成三端传输及 Ultra W 生命周期验收。验证证据锚定构建镜像、模块摘要与板端实测值，不绑定 Git 对象标识。
- 内核输出：`.config` 150,834 B、`scripts/module.lds` 977 B、`Module.symvers` 616,577 B，三者均存在且非零字节。
- Makefile：`make help`、默认、显式覆盖路径及 PATH 中裸 `CROSS_COMPILE` 前缀的 `prepare`/构建均返回 0；路径空白、主机 OS、主机架构、交叉编译器、`.config`、`scripts/module.lds`、`Module.symvers` 七类护栏均命中各自唯一诊断，后三项的缺失与零字节场景均被拒绝；连续两次 `make clean` 返回 0，清理后顶层 Kbuild 生成物为空，最终默认 `make` 成功。
- 模块：79,332 B；SHA-256 `c3f48770f72f08980cd8f24bb296010f0c55060075bb00ca5f261704850fdb68`；`ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV), BuildID[sha1]=e4558203df338d4f26eee776bffa7d96c598846a, with debug_info, not stripped`；完整 `vermagic=5.10.160 mod_unload ARMv7 thumb2 p2v8`。
- 传输与 ABI：编译机、macOS、开发板三处 SHA-256 完全一致；板端 `uname -r` 为 `5.10.160`，与 `vermagic` 的 release 一致。
- 板端生命周期：板端实测 `insmod` 返回 0，`/proc/modules` 为 `helloworld 827 0`，加载日志计数从 3 增至 4；板端实测 `rmmod` 返回 0，随后 `/proc/modules` 无模块，卸载日志计数从 3 增至 4；板端和 macOS 临时文件最终均不存在，`/oem/usr/ko/helloworld.ko` 不存在。
- 获批偏离及原因：远程分支准备增加失败即停、功能分支 refspec 幂等配置和五个暂存新增的精确恢复门禁，以处理远程仅抓取 `dev` 导致的失败切分支残留且避免误恢复其他改动；ADB 日志匹配先移除 CRLF，以保持 `$` 行尾断言有效；当前板端旧版 ADB shell 不向控制机传播远端退出码，因此模块命令在板端输出真实 `$?`，并以 `/proc/modules` 与日志增量交叉验证；本地 `rm -f` 在进程创建前被执行环境拒绝时，只对同一精确临时文件使用 `unlink`，以完成原定清理而不扩大删除范围。

---

### Task 1：实现最小 helloworld 内核模块

**Files:**

- Create: `sysdrv/drv_ko/examples/helloworld/helloworld.c`

**Interfaces:**

- Consumes: spec §2.1.2 内嵌的官方 `ko/helloworld.c` 基线。
- Produces: Kbuild 模块单元 `helloworld.o`，加载入口 `helloworld_init`，卸载入口 `helloworld_exit`。

- [x] **Step 1：确认新增路径尚不存在**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
test ! -e sysdrv/drv_ko/examples/helloworld/helloworld.c
```

期望：退出码为 0。若文件已存在，先检查其来源和内容，不覆盖未知改动。

- [x] **Step 2：创建 `helloworld.c`**

写入以下确定内容：

```c
// SPDX-License-Identifier: GPL-2.0-only

#include <linux/init.h>
#include <linux/module.h>

static int __init helloworld_init(void)
{
	pr_info("helloworld!\n");
	return 0;
}

static void __exit helloworld_exit(void)
{
	pr_info("helloworld bye\n");
}

module_init(helloworld_init);
module_exit(helloworld_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Luckfox");
MODULE_DESCRIPTION("Luckfox Pico external kernel module example");
MODULE_VERSION("V1.0");
```

- [x] **Step 3：静态核对行为和元数据**

```bash
grep -F 'static int __init helloworld_init(void)' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'static void __exit helloworld_exit(void)' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'pr_info("helloworld!\n");' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'pr_info("helloworld bye\n");' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'MODULE_LICENSE("GPL");' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'MODULE_AUTHOR("Luckfox");' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'MODULE_DESCRIPTION("Luckfox Pico external kernel module example");' sysdrv/drv_ko/examples/helloworld/helloworld.c
grep -F 'MODULE_VERSION("V1.0");' sysdrv/drv_ko/examples/helloworld/helloworld.c
```

期望：八条命令均只匹配一行。

---

### Task 2：实现独立双阶段 Kbuild Makefile

**Files:**

- Create: `sysdrv/drv_ko/examples/helloworld/Makefile`

**Interfaces:**

- Consumes: Task 1 的 `helloworld.c`，SDK 内核源码、`objs_kernel` 与内置交叉工具链。
- Produces: `all`、`prepare`、`clean`、`help` 四个公开目标、供 `prepare` 与 `clean` 共享的内部 `check-paths` 目标，以及调用内核 Kbuild 所需的五个可覆盖变量。

- [x] **Step 1：创建 Makefile**

Makefile 必须写入以下内容，配方行使用 Tab：

```make
# SPDX-License-Identifier: GPL-2.0-only

ifneq ($(KERNELRELEASE),)

obj-m := helloworld.o

else

SDK_ROOT ?= $(abspath $(CURDIR)/../../../..)
KDIR ?= $(SDK_ROOT)/sysdrv/source/kernel
KBUILD_OUTPUT ?= $(SDK_ROOT)/sysdrv/source/objs_kernel
ARCH ?= arm
CROSS_COMPILE ?= $(SDK_ROOT)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-

.PHONY: all prepare clean help check-paths

all: prepare
	$(MAKE) -C "$(KDIR)" O="$(KBUILD_OUTPUT)" M="$(CURDIR)" ARCH="$(ARCH)" CROSS_COMPILE="$(CROSS_COMPILE)" modules

prepare: check-paths
	@host_os="$$(uname -s)"; test "$$host_os" = "Linux" || { printf '%s\n' "error: unsupported host OS '$$host_os'; use Linux x86_64" >&2; exit 1; }
	@host_arch="$$(uname -m)"; test "$$host_arch" = "x86_64" || { printf '%s\n' "error: unsupported host architecture '$$host_arch'; use Linux x86_64" >&2; exit 1; }
	@compiler="$(CROSS_COMPILE)gcc"; case "$$compiler" in */*) test -x "$$compiler";; *) command -v "$$compiler" >/dev/null 2>&1;; esac && "$$compiler" --version >/dev/null 2>&1 || { printf '%s\n' "error: cross compiler is missing or not executable: $$compiler" >&2; exit 1; }
	@test -s "$(KBUILD_OUTPUT)/.config" || { printf '%s\n' "error: missing or empty kernel configuration: $(KBUILD_OUTPUT)/.config" >&2; exit 1; }
	@test -s "$(KBUILD_OUTPUT)/scripts/module.lds" || { printf '%s\n' "error: missing or empty module linker script: $(KBUILD_OUTPUT)/scripts/module.lds" >&2; exit 1; }
	@test -s "$(KBUILD_OUTPUT)/Module.symvers" || { printf '%s\n' "error: missing or empty kernel symbol versions: $(KBUILD_OUTPUT)/Module.symvers" >&2; exit 1; }

check-paths:
	@case "$(CURDIR)" in *[[:space:]]*) printf '%s\n' "error: CURDIR must not contain whitespace: $(CURDIR)" >&2; exit 1;; esac
	@case "$(SDK_ROOT)" in *[[:space:]]*) printf '%s\n' "error: SDK_ROOT must not contain whitespace: $(SDK_ROOT)" >&2; exit 1;; esac
	@case "$(KDIR)" in *[[:space:]]*) printf '%s\n' "error: KDIR must not contain whitespace: $(KDIR)" >&2; exit 1;; esac
	@case "$(KBUILD_OUTPUT)" in *[[:space:]]*) printf '%s\n' "error: KBUILD_OUTPUT must not contain whitespace: $(KBUILD_OUTPUT)" >&2; exit 1;; esac
	@case "$(CROSS_COMPILE)" in *[[:space:]]*) printf '%s\n' "error: CROSS_COMPILE must not contain whitespace: $(CROSS_COMPILE)" >&2; exit 1;; esac

clean: check-paths
	$(MAKE) -C "$(KDIR)" O="$(KBUILD_OUTPUT)" M="$(CURDIR)" ARCH="$(ARCH)" CROSS_COMPILE="$(CROSS_COMPILE)" clean

help:
	@printf '%s\n' \
		"Luckfox Pico external kernel module example" \
		"" \
		"Targets:" \
		"  all      Check prerequisites and build helloworld.ko (default)" \
		"  prepare  Check the host, toolchain and kernel build output" \
		"  clean    Remove files generated by Kbuild for this example" \
		"  help     Show this help" \
		"" \
		"Variables:" \
		"  SDK_ROOT=$(SDK_ROOT)" \
		"  KDIR=$(KDIR)" \
		"  KBUILD_OUTPUT=$(KBUILD_OUTPUT)" \
		"  ARCH=$(ARCH)" \
		"  CROSS_COMPILE=$(CROSS_COMPILE)" \
		"" \
		"Example:" \
		"  make" \
		"  make KBUILD_OUTPUT=/path/to/matching/objs_kernel" \
		"" \
		"helloworld.ko must be built against the kernel configuration and output matching the running board."

endif
```

`all` 是普通 Make 分支的第一个普通目标，因此 GNU Make 会在直接执行 `make` 时将其作为默认目标；不设置显式默认目标，避免干扰 Kbuild 的外置模块清理。

- [x] **Step 2：在 macOS 验证无内核产物时 `help` 仍可用**

```bash
cd sysdrv/drv_ko/examples/helloworld
make help
```

期望：退出码为 0，显示四个目标、五个变量的当前解析值和 ABI 匹配提示。

- [x] **Step 3：在 macOS 验证 `prepare` 提前拒绝错误主机**

```bash
if make prepare >/tmp/helloworld-macos-prepare.log 2>&1; then
	echo "unexpected success"
	exit 1
fi
grep -F "error: unsupported host OS 'Darwin'; use Linux x86_64" /tmp/helloworld-macos-prepare.log
```

期望：`prepare` 非零退出，且尚未调用交叉编译器或内核 Kbuild。

---

### Task 3：编写面向初学者的中文 README

**Files:**

- Create: `sysdrv/drv_ko/examples/helloworld/README.md`

**Interfaces:**

- Consumes: Task 1 的模块行为、Task 2 的构建接口、spec 固定的官方来源与哈希。
- Produces: 面向初学者的构建、传输、ABI 检查、加载、卸载与故障诊断文档。

- [x] **Step 1：写明例程身份和集成边界**

README 必须说明：

- 这是 Linux 外置内核模块，不是用户空间程序。
- 代码派生自 Luckfox 官方 `ko.zip`。
- 官方 `ko/Makefile` SHA-256 为 `c99e6f79ba455b245c5873699f755fd526687b4159f7f69988d90865a890763e`。
- 官方 `ko/helloworld.c` SHA-256 为 `360e744ec4fcb88f51d46873c4efeda12b3023317dca10a179509ffd16f2265d`。
- 仓库版本的 `helloworld.c` 相对官方源码增加 SPDX、`__init`/`__exit`、`pr_info` 和 `MODULE_DESCRIPTION`，Makefile 从固定绝对路径脚本重构为相对默认路径、可覆盖变量、前置检查及 `clean`/`help` 目标完整的双阶段入口；日志文本和官方模块元数据保持兼容。
- 例程未加入父级 `M_DIRS`，不会被 `./build.sh` 自动构建，也不会进入 `/oem/usr/ko`。
- 使用者必须主动进入本目录运行 `make`，并将生成的 `.ko` 放到开发板临时目录验证。

- [x] **Step 2：解释编译机、macOS 和开发板的职责**

README 固定区分：

1. linux/amd64 Ubuntu 24.04：选择 Ultra W、准备内核输出、交叉编译模块。
2. macOS：从编译机取得 `.ko`、核对 SHA-256、通过 ADB 传到开发板。
3. Luckfox Pico Ultra W：只负责 `insmod`、`/proc/modules`、`dmesg` 和 `rmmod`。

明确说明 macOS 无法原生运行仓库内的 Linux x86-64 工具链，开发板也不能执行该工具链。

远程 SSH/SCP 示例必须从 `LUCKFOX_SSH_PORT` 读取端口，并以 `: "${LUCKFOX_SSH_PORT:?...}"` 在连接前检查变量；不得给出默认值、示例值或真实端口。远程仓库直接使用 `/data/luckfox-pico` 当前工作树，不创建 worktree。

- [x] **Step 3：写入正确的内核准备命令**

README 不得声称 `./build.sh kernel` 单独即可准备外置模块。固定使用：

```bash
cd /workspace/luckfox-pico
printf '5\n0\n0\n' | ./build.sh lunch
./build.sh kernel

SDK_ROOT=/workspace/luckfox-pico
KBUILD_OUTPUT="$SDK_ROOT/sysdrv/source/objs_kernel"
CROSS_COMPILE="$SDK_ROOT/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-"

make -C "$SDK_ROOT/sysdrv/source/kernel" \
	O="$KBUILD_OUTPUT" \
	ARCH=arm \
	CROSS_COMPILE="$CROSS_COMPILE" \
	modules \
	-j"$(nproc)"
```

解释 `./build.sh kernel` 在当前 out-of-tree 输出模式下只构建 DTB、`zImage`、`Image.gz` 和镜像，不会自动执行 `modules`；后续显式命令用于生成外置模块依赖的 `scripts/module.lds` 和完整 `Module.symvers`。

- [x] **Step 4：写入模块构建、变量覆盖和故障诊断**

最小构建命令：

```bash
cd /workspace/luckfox-pico/sysdrv/drv_ko/examples/helloworld
make
```

README 逐项解释 `SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT`、`ARCH`、`CROSS_COMPILE` 和 `M=$(CURDIR)`，并说明：

- 命令行变量覆盖优先于 Makefile 默认值。
- 路径不得包含空白字符。
- 缺少 `.config`、`scripts/module.lds` 或 `Module.symvers` 时应重新执行对应内核准备步骤。
- `Invalid module format` 首先查看紧随失败后的 `dmesg`，禁止使用 `insmod -f` 绕过。
- `uname -r` 只校验 `vermagic` 的 release 部分，最终 ABI 判断以模块加载器和 `dmesg` 为准。

- [x] **Step 5：写入传输和板端验收命令**

README 必须包含编译机、macOS、开发板三处 SHA-256 对照，以及：

```bash
adb push /tmp/helloworld.ko /tmp/helloworld.ko
adb shell sha256sum /tmp/helloworld.ko
adb shell uname -r
adb shell "strings /tmp/helloworld.ko | grep '^vermagic='"
adb shell insmod /tmp/helloworld.ko
adb shell lsmod
adb shell dmesg
adb shell rmmod helloworld
adb shell dmesg
adb shell rm -f /tmp/helloworld.ko
```

`lsmod` 在 README 中作为读取 `/proc/modules` 的等价用户接口；Task 5 的验收命令直接读取 `/proc/modules`。

不得指示使用者写入 `/oem/usr/ko` 或配置自动加载。

- [x] **Step 6：检查 README 不包含失效路径和越界说明**

```bash
rg -n '/home/ubuntu/Luckfox/sdk-1015|/oem/usr/ko|release_.*rv1106' sysdrv/drv_ko/examples/helloworld/README.md
```

期望：可以在历史来源或“不写入 `/oem/usr/ko`”的否定说明中出现，但不得作为当前构建、安装或发布路径。

---

### Task 4：提交功能文件并在远程 Ubuntu 24.04 环境构建

**Files:**

- Verify: `sysdrv/drv_ko/examples/helloworld/helloworld.c`
- Verify: `sysdrv/drv_ko/examples/helloworld/Makefile`
- Verify: `sysdrv/drv_ko/examples/helloworld/README.md`

**Interfaces:**

- Consumes: Task 1–3 的完整例程。
- Produces: 已推送的功能提交、切换到当前开发分支的远程仓库、经过正负向验证的 ARM EABI5 `helloworld.ko`。

- [x] **Step 1：限定路径检查并提交三个例程文件**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
git diff --check -- sysdrv/drv_ko/examples/helloworld
git status --short -- sysdrv/drv_ko/examples/helloworld
git add -- sysdrv/drv_ko/examples/helloworld/helloworld.c sysdrv/drv_ko/examples/helloworld/Makefile sysdrv/drv_ko/examples/helloworld/README.md
git diff --cached --check
git diff --cached --stat
git cz
git push origin codex/helloworld-kernel-module-example
```

提交只包含三个例程文件；使用 Conventional + gitmoji，subject 只表达“增加 helloworld 外置内核模块例程”，body 记录位置选择、独立构建边界和 ABI 匹配约束，不粘贴实现清单。

- [x] **Step 2：在远程机直接切换到当前开发分支**

登录：

```bash
: "${LUCKFOX_SSH_PORT:?set LUCKFOX_SSH_PORT in the local environment}"
ssh -p "$LUCKFOX_SSH_PORT" root@mastodon.yuangezhizao.cn
```

在远程机执行：

```bash
cd /data/luckfox-pico
set -euo pipefail
git status --short --branch

feature_refspec='+refs/heads/codex/helloworld-kernel-module-example:refs/remotes/origin/codex/helloworld-kernel-module-example'
git config --get-all remote.origin.fetch | grep -Fx "$feature_refspec" >/dev/null || git config --add remote.origin.fetch "$feature_refspec"
git fetch origin "$feature_refspec"

approved_recovery_changes="$(printf '%s\n' \
	'A  docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md' \
	'A  docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md' \
	'A  sysdrv/drv_ko/examples/helloworld/Makefile' \
	'A  sysdrv/drv_ko/examples/helloworld/README.md' \
	'A  sysdrv/drv_ko/examples/helloworld/helloworld.c')"
current_changes="$(git status --porcelain)"

if test "$current_changes" = "$approved_recovery_changes"; then
	current_branch="$(git branch --show-current)"
	current_head="$(git rev-parse HEAD)"
	dev_head="$(git rev-parse origin/dev)"
	test "$current_branch" = "dev"
	test "$current_head" = "$dev_head"
	git diff --cached --quiet origin/codex/helloworld-kernel-module-example -- \
		docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md \
		docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
		sysdrv/drv_ko/examples/helloworld/Makefile \
		sysdrv/drv_ko/examples/helloworld/README.md \
		sysdrv/drv_ko/examples/helloworld/helloworld.c
	git diff --quiet -- \
		docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md \
		docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
		sysdrv/drv_ko/examples/helloworld/Makefile \
		sysdrv/drv_ko/examples/helloworld/README.md \
		sysdrv/drv_ko/examples/helloworld/helloworld.c
	git restore --source=HEAD --staged --worktree -- \
		docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md \
		docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
		sysdrv/drv_ko/examples/helloworld/Makefile \
		sysdrv/drv_ko/examples/helloworld/README.md \
		sysdrv/drv_ko/examples/helloworld/helloworld.c
fi

unexpected_changes="$(git status --porcelain | sed \
	-e '\|^ M project/app/wifi_app/hostapd-2.6/hostapd/hostapd$|d' \
	-e '\|^ M project/app/wifi_app/hostapd-2.6/hostapd/hostapd_cli$|d' \
	-e '\|^ M project/app/wifi_app/wifi/librkwifibt.so$|d')"

if test -n "$unexpected_changes"; then
	printf '%s\n' "$unexpected_changes" >&2
	exit 1
fi

git restore -- \
	project/app/wifi_app/hostapd-2.6/hostapd/hostapd \
	project/app/wifi_app/hostapd-2.6/hostapd/hostapd_cli \
	project/app/wifi_app/wifi/librkwifibt.so

tracked_changes="$(git status --porcelain --untracked-files=no)"
test -z "$tracked_changes"
git fetch origin "$feature_refspec"

if git show-ref --verify --quiet refs/heads/codex/helloworld-kernel-module-example; then
	git switch codex/helloworld-kernel-module-example
	git merge --ff-only origin/codex/helloworld-kernel-module-example
else
	git switch --track -c codex/helloworld-kernel-module-example origin/codex/helloworld-kernel-module-example
fi

current_head="$(git rev-parse HEAD)"
feature_head="$(git rev-parse origin/codex/helloworld-kernel-module-example)"
test "$current_head" = "$feature_head"
```

远程脚本启用 `set -euo pipefail`，任一断言、抓取或比较失败都会在 restore 或切分支前停止。功能分支 refspec 在恢复判断前无条件配置并显式抓取，使干净环境和恢复环境共用同一远程跟踪引用。已批准的恢复分支只处理失败切分支留下的五个精确暂存新增：必须确认远程仍位于与 `origin/dev` 一致的 `dev`、索引内容与功能分支完全一致且工作树相对索引无差异，才从当前 `dev` HEAD 按精确路径恢复；这些内容可由已推送的功能分支重新取得。除此之外，切换前 `git status` 只允许出现 AGENTS.md 已登记的 `hostapd`、`hostapd_cli`、`librkwifibt.so` 三个可再生构建噪音；若出现其他 tracked 修改，必须停止，不执行 `git restore` 或切分支。期望切换后远程 HEAD 与刚推送的功能提交一致，并保持在 `codex/helloworld-kernel-module-example`。

- [x] **Step 3：从当前 `.cursor/Dockerfile` 构建 linux/amd64 Ubuntu 24.04 镜像**

```bash
docker build \
	--platform linux/amd64 \
	-t luckfox-pico-helloworld:ubuntu24.04 \
	-f /data/luckfox-pico/.cursor/Dockerfile \
	/data/luckfox-pico
```

期望：构建成功；不得改用现有 `luckfoxtech/luckfox_pico:1.0` 容器替代正式验收。若标准构建仅因远程下载网络失败，可在同一命令临时增加 `--build-arg https_proxy=http://10.0.2.2:1080` 后重试；不修改 Dockerfile，也不写入全局 Git/Docker 配置。

- [x] **Step 4：准备 Ultra W 内核输出并显式构建内核模块目标**

```bash
docker run --rm \
	--platform linux/amd64 \
	-v /data/luckfox-pico:/workspace/luckfox-pico \
	-w /workspace/luckfox-pico \
	luckfox-pico-helloworld:ubuntu24.04 \
	bash -lc '
		set -e
		printf "5\n0\n0\n" | ./build.sh lunch
		./build.sh kernel
		make -C /workspace/luckfox-pico/sysdrv/source/kernel \
			O=/workspace/luckfox-pico/sysdrv/source/objs_kernel \
			ARCH=arm \
			CROSS_COMPILE=/workspace/luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf- \
			modules \
			-j"$(nproc)"
		test -s sysdrv/source/objs_kernel/.config
		test -s sysdrv/source/objs_kernel/scripts/module.lds
		test -s sysdrv/source/objs_kernel/Module.symvers
	'
```

期望：全部退出码为 0，三个内核准备文件存在且非空。

- [x] **Step 5：执行 Makefile 正向、负向和清理测试**

在同一 Ubuntu 24.04 镜像中验证：

```bash
install -d /tmp/luckfox-helloworld

docker run --rm \
	--platform linux/amd64 \
	-v /data/luckfox-pico:/workspace/luckfox-pico \
	-v /tmp/luckfox-helloworld:/artifacts \
	-w /workspace/luckfox-pico/sysdrv/drv_ko/examples/helloworld \
	luckfox-pico-helloworld:ubuntu24.04 \
	bash -lc '
		set -euo pipefail
		make help
		make prepare

		if setarch linux32 make prepare >/tmp/helloworld-arch.log 2>&1; then exit 1; fi
		grep -F "error: unsupported host architecture" /tmp/helloworld-arch.log

		if make prepare SDK_ROOT="/tmp/path with space" >/tmp/helloworld-sdk-root-space.log 2>&1; then exit 1; fi
		grep -F "error: SDK_ROOT must not contain whitespace" /tmp/helloworld-sdk-root-space.log

		if make prepare KDIR="/tmp/path with space" >/tmp/helloworld-kdir-space.log 2>&1; then exit 1; fi
		grep -F "error: KDIR must not contain whitespace" /tmp/helloworld-kdir-space.log

		if make prepare KBUILD_OUTPUT="/tmp/path with space" >/tmp/helloworld-kbuild-output-space.log 2>&1; then exit 1; fi
		grep -F "error: KBUILD_OUTPUT must not contain whitespace" /tmp/helloworld-kbuild-output-space.log

		if make prepare CROSS_COMPILE="/tmp/tool chain-" >/tmp/helloworld-cross-compile-space.log 2>&1; then exit 1; fi
		grep -F "error: CROSS_COMPILE must not contain whitespace" /tmp/helloworld-cross-compile-space.log

		space_root="$(mktemp -d)"
		space_fixture="$space_root/example with space"
		install -d "$space_fixture"
		cp Makefile helloworld.c "$space_fixture/"
		if make -C "$space_fixture" prepare >/tmp/helloworld-curdir-prepare-space.log 2>&1; then exit 1; fi
		grep -F "error: CURDIR must not contain whitespace" /tmp/helloworld-curdir-prepare-space.log
		if make -C "$space_fixture" clean >/tmp/helloworld-curdir-clean-space.log 2>&1; then exit 1; fi
		grep -F "error: CURDIR must not contain whitespace" /tmp/helloworld-curdir-clean-space.log

		if make prepare CROSS_COMPILE=/tmp/missing-toolchain- >/tmp/helloworld-toolchain.log 2>&1; then exit 1; fi
		grep -F "error: cross compiler is missing or not executable" /tmp/helloworld-toolchain.log

		toolchain_bin=/workspace/luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin
		PATH="$toolchain_bin:$PATH" make prepare CROSS_COMPILE=arm-rockchip830-linux-uclibcgnueabihf-
		PATH="$toolchain_bin:$PATH" make CROSS_COMPILE=arm-rockchip830-linux-uclibcgnueabihf-

		config_fixture="$(mktemp -d)"
		if make prepare KBUILD_OUTPUT="$config_fixture" >/tmp/helloworld-config.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty kernel configuration" /tmp/helloworld-config.log
		touch "$config_fixture/.config"
		if make prepare KBUILD_OUTPUT="$config_fixture" >/tmp/helloworld-config-empty.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty kernel configuration" /tmp/helloworld-config-empty.log

		lds_fixture="$(mktemp -d)"
		mkdir -p "$lds_fixture/scripts"
		cp /workspace/luckfox-pico/sysdrv/source/objs_kernel/.config "$lds_fixture/.config"
		if make prepare KBUILD_OUTPUT="$lds_fixture" >/tmp/helloworld-lds.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty module linker script" /tmp/helloworld-lds.log
		touch "$lds_fixture/scripts/module.lds"
		if make prepare KBUILD_OUTPUT="$lds_fixture" >/tmp/helloworld-lds-empty.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty module linker script" /tmp/helloworld-lds-empty.log

		symvers_fixture="$(mktemp -d)"
		mkdir -p "$symvers_fixture/scripts"
		cp /workspace/luckfox-pico/sysdrv/source/objs_kernel/.config "$symvers_fixture/.config"
		cp /workspace/luckfox-pico/sysdrv/source/objs_kernel/scripts/module.lds "$symvers_fixture/scripts/module.lds"
		if make prepare KBUILD_OUTPUT="$symvers_fixture" >/tmp/helloworld-symvers.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty kernel symbol versions" /tmp/helloworld-symvers.log
		touch "$symvers_fixture/Module.symvers"
		if make prepare KBUILD_OUTPUT="$symvers_fixture" >/tmp/helloworld-symvers-empty.log 2>&1; then exit 1; fi
		grep -F "error: missing or empty kernel symbol versions" /tmp/helloworld-symvers-empty.log

		make prepare SDK_ROOT=/workspace/luckfox-pico KBUILD_OUTPUT=/workspace/luckfox-pico/sysdrv/source/objs_kernel
		make SDK_ROOT=/workspace/luckfox-pico KBUILD_OUTPUT=/workspace/luckfox-pico/sysdrv/source/objs_kernel
		make clean
		make clean
		test -z "$(find . -maxdepth 1 \( -name "*.ko" -o -name "*.o" -o -name "*.cmd" -o -name "*.mod" -o -name "*.mod.c" -o -name "Module.symvers" -o -name "modules.order" \) -print -quit)"
		make 2>&1 | tee /artifacts/build.log
	'
```

在独立临时例程目录复验普通默认构建、正常清理和空 `include/config/kernel.release` 清理，不修改远程仓库中的跟踪文件：

```bash
clean_fixture="$(mktemp -d /tmp/luckfox-helloworld-clean.XXXXXX)"
trap 'rm -rf -- "$clean_fixture"' EXIT
clean_module="$clean_fixture/sysdrv/drv_ko/examples/helloworld"
install -d "$clean_module"
ln -s /data/luckfox-pico/sysdrv/source "$clean_fixture/sysdrv/source"
ln -s /data/luckfox-pico/tools "$clean_fixture/tools"
cp \
	/data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/Makefile \
	/data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/helloworld.c \
	"$clean_module/"
touch "$clean_fixture/empty-kernel.release"

docker run --rm \
	--platform linux/amd64 \
	-v /data/luckfox-pico:/data/luckfox-pico:ro \
	-v "$clean_fixture:/fixture" \
	-w /fixture/sysdrv/drv_ko/examples/helloworld \
	luckfox-pico-helloworld:ubuntu24.04 \
	bash -lc 'set -euo pipefail; make; test -s helloworld.ko; make clean; make; test -s helloworld.ko'

before_empty_clean="$(find "$clean_module" -maxdepth 1 \( -name "*.ko" -o -name "*.o" -o -name ".*.cmd" -o -name "*.mod" -o -name "*.mod.c" -o -name "Module.symvers" -o -name "modules.order" \) -print | wc -l | tr -d ' ')"
docker run --rm \
	--platform linux/amd64 \
	-v /data/luckfox-pico:/data/luckfox-pico:ro \
	-v "$clean_fixture:/fixture" \
	-v "$clean_fixture/empty-kernel.release:/data/luckfox-pico/sysdrv/source/objs_kernel/include/config/kernel.release:ro" \
	-w /fixture/sysdrv/drv_ko/examples/helloworld \
	luckfox-pico-helloworld:ubuntu24.04 \
	make clean
after_empty_clean="$(find "$clean_module" -maxdepth 1 \( -name "*.ko" -o -name "*.o" -o -name ".*.cmd" -o -name "*.mod" -o -name "*.mod.c" -o -name "Module.symvers" -o -name "modules.order" \) -print | wc -l | tr -d ' ')"
printf 'empty_kernel_release_clean_artifacts=%s->%s\n' "$before_empty_clean" "$after_empty_clean"
test "$before_empty_clean" -eq 13
test "$after_empty_clean" -eq 0
```

期望：五个路径变量的空白场景均命中各自唯一诊断，`clean` 与 `prepare` 对 `CURDIR` 使用同一诊断；`.config`、`scripts/module.lds`、`Module.symvers` 缺失或为零字节时均被拒绝；完整路径前缀、显式覆盖 `SDK_ROOT`/`KBUILD_OUTPUT` 及 PATH 中裸 `CROSS_COMPILE` 前缀的正向构建均成功；两次 `clean` 均成功；独立临时目录的普通 `make` 两次生成 `helloworld.ko`，正常 `make clean` 返回 0，空 `kernel.release` 场景的 `make clean` 也返回 0，顶层 Kbuild 产物实测从 13 个清为 0；最终重新生成 `helloworld.ko`，完整构建日志保存到 `/tmp/luckfox-helloworld/build.log`。

- [x] **Step 6：检查模块格式、元数据和构建日志**

```bash
docker run --rm \
	--platform linux/amd64 \
	-v /data/luckfox-pico:/workspace/luckfox-pico \
	-v /tmp/luckfox-helloworld:/artifacts \
	-w /workspace/luckfox-pico/sysdrv/drv_ko/examples/helloworld \
	luckfox-pico-helloworld:ubuntu24.04 \
	bash -lc '
		set -euo pipefail
		test -s /artifacts/build.log
		if grep -E "WARNING: Symbol version dump .* is missing|ERROR: modpost:|undefined!|(^|[[:space:]])error:" /artifacts/build.log; then exit 1; fi

		readelf=/workspace/luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-readelf
		module_info="$($readelf -p .modinfo helloworld.ko)"
		for field in \
			"license=GPL" \
			"author=Luckfox" \
			"description=Luckfox Pico external kernel module example" \
			"version=V1.0" \
			"name=helloworld" \
			"vermagic="; do
			printf "%s\n" "$module_info" | grep -F "$field" >/dev/null
		done

		file_output="$(file helloworld.ko)"
		printf "%s\n" "$file_output" | grep -F "ELF 32-bit LSB relocatable, ARM, EABI5" >/dev/null
		module_size="$(stat -c "%s" helloworld.ko)"
		test "$module_size" -gt 0
		vermagic_line="$(printf "%s\n" "$module_info" | grep -F "vermagic=" | head -n 1)"
		module_sha="$(sha256sum helloworld.ko | awk "{print \$1}")"

		{
			printf "file=%s\n" "$file_output"
			printf "size_bytes=%s\n" "$module_size"
			printf "sha256=%s\n" "$module_sha"
			printf "%s\n" "$vermagic_line"
			printf "%s\n" "$module_info"
		} | tee /artifacts/module-evidence.txt
	'
```

验收：

- `file` 报告 `ELF 32-bit LSB relocatable, ARM, EABI5`。
- 六个模块元数据字段分别断言存在，不能由单个 alternation 匹配代替。
- 保存的完整构建日志不存在 missing `Module.symvers`、unresolved symbol、modpost、编译或链接错误。
- `/tmp/luckfox-helloworld/module-evidence.txt` 记录最终 `.ko` 字节数、SHA-256、文件类型、完整 `vermagic` 和 `.modinfo`，但不把这些会随内核构建变化的值硬编码进 README。

---

### Task 5：在 Ultra W 开发板完成端到端验收

**Files:**

- Runtime artifact only: `/tmp/helloworld.ko`
- No repository changes during this task

**Interfaces:**

- Consumes: Task 4 的 `helloworld.ko` 和 SHA-256。
- Produces: 三端哈希、ABI 初筛、加载/卸载返回值、`/proc/modules` 状态及两条新增内核日志。

- [x] **Step 1：确认 macOS 只连接了一台已授权的 ADB 设备**

```bash
adb devices -l
adb_devices="$(adb devices)" || exit 1
test "$(printf '%s\n' "$adb_devices" | awk 'NR>1 && NF { count++ } END { print count+0 }')" -eq 1
test "$(printf '%s\n' "$adb_devices" | awk 'NR>1 && $2=="device" { count++ } END { print count+0 }')" -eq 1
adb shell uname -a
```

若没有设备、设备未授权或存在多台设备，停止验收，不猜测目标序列号。

- [x] **Step 2：从远程编译机取得模块并核对前两处 SHA-256**

```bash
: "${LUCKFOX_SSH_PORT:?set LUCKFOX_SSH_PORT in the local environment}"

ssh -p "$LUCKFOX_SSH_PORT" root@mastodon.yuangezhizao.cn \
	'sha256sum /data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/helloworld.ko'

scp -P "$LUCKFOX_SSH_PORT" \
	root@mastodon.yuangezhizao.cn:/data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/helloworld.ko \
	/tmp/helloworld.ko

shasum -a 256 /tmp/helloworld.ko
```

期望：远程编译机和 macOS 的 SHA-256 完全一致。

- [x] **Step 3：传到开发板并核对第三处 SHA-256**

```bash
adb push /tmp/helloworld.ko /tmp/helloworld.ko
adb shell sha256sum /tmp/helloworld.ko
```

期望：板端 SHA-256 与前两处一致。

- [x] **Step 4：执行 ABI 初筛**

```bash
adb shell uname -r
adb shell "strings /tmp/helloworld.ko | grep '^vermagic='"
```

期望：`uname -r` 与 `vermagic` 的 release 部分一致。该检查不是最终 ABI 证明。

- [x] **Step 5：建立干净基线并加载模块**

若 `/proc/modules` 已出现 `helloworld`，先执行 `adb shell rmmod helloworld`；若卸载失败则停止，不继续覆盖现场。

记录加载前日志计数，然后加载：

```bash
before_load="$(adb shell dmesg | tr -d '\r' | grep -c 'helloworld!$')"
insmod_status="$(adb shell 'insmod /tmp/helloworld.ko; printf "INSMOD_RC=%s\n" "$?"' | tr -d '\r')"
test "$insmod_status" = "INSMOD_RC=0"
module_state="$(adb shell "awk '\$1 == \"helloworld\" { print \$0 }' /proc/modules" | tr -d '\r')"
printf '%s\n' "$module_state" | awk '$1=="helloworld" && $3=="0" { found=1 } END { exit !found }'
after_load="$(adb shell dmesg | tr -d '\r' | grep -c 'helloworld!$')"
test "$after_load" -eq "$((before_load + 1))"
```

期望：`insmod` 返回 0，`/proc/modules` 显示引用计数 0，新增且仅新增一条 `helloworld!`。

- [x] **Step 6：卸载模块并验证退出日志**

```bash
before_unload="$(adb shell dmesg | tr -d '\r' | grep -c 'helloworld bye$')"
rmmod_status="$(adb shell 'rmmod helloworld; printf "RMMOD_RC=%s\n" "$?"' | tr -d '\r')"
test "$rmmod_status" = "RMMOD_RC=0"
module_state="$(adb shell "awk '\$1 == \"helloworld\" { print \$0 }' /proc/modules" | tr -d '\r')"
if test -n "$module_state"; then
	echo "helloworld is still loaded"
	exit 1
fi
after_unload="$(adb shell dmesg | tr -d '\r' | grep -c 'helloworld bye$')"
test "$after_unload" -eq "$((before_unload + 1))"
```

期望：`rmmod` 返回 0，模块从 `/proc/modules` 消失，新增且仅新增一条 `helloworld bye`。

- [x] **Step 7：清理临时文件**

```bash
adb shell rm -f /tmp/helloworld.ko
rm -f /tmp/helloworld.ko
test "$(adb shell 'if test -e /tmp/helloworld.ko; then echo present; else echo absent; fi' | tr -d '\r')" = absent
test ! -e /tmp/helloworld.ko
```

只删除上述两个明确的临时文件，不修改 `/oem/usr/ko`。

若执行环境在本地 `rm -f /tmp/helloworld.ko` 启动前拒绝执行，只允许对同一精确路径改用 `unlink /tmp/helloworld.ko`，随后仍须执行板端与本地的不存在断言。

---

### Task 6：回填验证证据、验证提交边界并更新 PR

**Files:**

- Modify: `docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md`
- Modify: `docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md`

**Interfaces:**

- Consumes: Task 1–5 的实现和可复现验证证据。
- Produces: 只呈现当前结论、证据和获批偏离的最终 spec/plan。

- [x] **Step 1：向 spec 和 plan 回填精简、可复现的验证证据并更新状态**

只回填：

- Task 1–5 全部通过后，才将 spec 与 plan 的状态更新为已实施并通过验收。
- 验证使用模块 SHA-256、Ubuntu 24.04 镜像 ID 与板端实测值，不使用 Git 对象标识作为验收锚点。
- `.config`、`scripts/module.lds`、`Module.symvers` 的存在性及非零字节结果。
- `helloworld.ko` 的字节数、SHA-256、文件类型和完整 `vermagic`。
- Makefile 正向、七类前置检查、重复清理的结果。
- 编译机、macOS、开发板三处 SHA-256。
- `insmod`、`/proc/modules`、加载日志、`rmmod`、卸载日志的实测结果。
- 如发生经用户批准的计划偏离，只记录偏离内容和原因，不写操作流水。

- [x] **Step 2：确认生成物未被跟踪、暂存或提交，并排除范围外改动**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
tracked_example_files="$(git ls-files sysdrv/drv_ko/examples/helloworld)"
printf '%s\n' "$tracked_example_files"
test "$(printf '%s\n' "$tracked_example_files" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 3
for expected in \
	sysdrv/drv_ko/examples/helloworld/Makefile \
	sysdrv/drv_ko/examples/helloworld/README.md \
	sysdrv/drv_ko/examples/helloworld/helloworld.c; do
	printf '%s\n' "$tracked_example_files" | grep -Fx "$expected" >/dev/null
done

generated_pattern='(\.ko|\.o|\.cmd|\.mod|\.mod\.c|Module\.symvers|modules\.order)$|/\.tmp_versions/'
tracked_generated="$(printf '%s\n' "$tracked_example_files" | grep -E "$generated_pattern" || true)"
test -z "$tracked_generated"
staged_generated="$(git diff --cached --name-only -- sysdrv/drv_ko/examples/helloworld | grep -E "$generated_pattern" || true)"
test -z "$staged_generated"

git status --short -- \
	sysdrv/drv_ko/examples/helloworld \
	docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
	docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md

git diff --check -- \
	sysdrv/drv_ko/examples/helloworld \
	docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
	docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md
```

期望：Git 只跟踪例程的 `helloworld.c`、Makefile、README；不存在被跟踪或暂存的 Kbuild 产物；文档改动只包含 spec 和 plan。远程工作目录可以保留被 `.gitignore` 覆盖的 Kbuild 生成物。

- [x] **Step 3：将 Superpowers 文档作为 PR 最后一次提交**

```bash
git add -- \
	docs/superpowers/specs/2026-08-26-luckfox-external-kernel-module-helloworld-design.md \
	docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md

git diff --cached --check
git diff --cached --stat
git cz
git push origin codex/helloworld-kernel-module-example
```

该提交只包含 spec 和 plan，使用 Conventional + gitmoji；subject 表达文档交付主题，body 记录关键设计依据和构建 gotcha，并保留一个 spec 章节指针，不粘贴命令输出或实施流水。

- [x] **Step 4：核对 PR 元数据与提交边界**

```bash
gh pr view 7 --json number,title,baseRefName,headRefName,url,commits
```

验收：

- base 为 `dev`，head 为 `codex/helloworld-kernel-module-example`。
- 功能提交在前，Superpowers 文档提交位于最后。

## Acceptance Criteria

- 仓库新增且只新增例程所需的 `helloworld.c`、Makefile、README、spec 和 plan；spec 与 plan 只保留当前设计结论、约束和最终验证证据。
- 默认 `make` 可以在准备完整的 linux/amd64 Ubuntu 24.04 环境生成 ARM EABI5 `helloworld.ko`。
- `make help` 不依赖内核输出；七项 `prepare` 护栏均有明确、唯一的失败诊断；`make clean` 可重复执行。
- 模块元数据完整，三处 SHA-256 一致，Ultra W 上加载和卸载均成功并产生预期日志。
- 例程不进入 SDK 自动构建或 OEM 打包链路，任何 Kbuild 生成物都不被 Git 跟踪、暂存或提交；远程工作目录可以保留被 `.gitignore` 覆盖的生成物。
- PR #7 的 base 为 `dev`，合并操作只由维护者执行。

## Assumptions

- 实施阶段开发板会重新连接到当前 macOS，并能被 `adb devices` 唯一识别和授权。
- Ultra W 正在运行的内核与本分支使用的 Linux 5.10.160 源码、Ultra W 配置及 `objs_kernel` 匹配；若实际 `vermagic` 不匹配，停止验收并报告固件来源，不强制加载。
- `mastodon.yuangezhizao.cn` 保持免密 root SSH，macOS 控制机已在未入库的 `LUCKFOX_SSH_PORT` 中设置端口；远程 `/data/luckfox-pico` 仓库和 Docker 服务可用。
- 当前 spec 已确定的 GPL-2.0-only 派生策略保持不变，本 plan 不重新作许可证决策。
