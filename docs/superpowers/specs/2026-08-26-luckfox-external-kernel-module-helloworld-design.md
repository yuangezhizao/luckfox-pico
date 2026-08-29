# Luckfox Pico 外置内核模块 helloworld 例程设计规格（Design Spec）

- **日期**：2026-08-26
- **状态**：已实施并通过 linux/amd64 Ubuntu 24.04 构建验收与 Luckfox Pico Ultra W 板端验收
- **分支**：`codex/helloworld-kernel-module-example`（起点为创建分支时最新的 `dev`）
- **主题**：在 Luckfox Pico SDK 中增加一个可独立构建、可在开发板动态加载的 Linux 外置内核模块教学例程
- **关联代码文件**：`sysdrv/drv_ko/examples/helloworld/helloworld.c`、`sysdrv/drv_ko/examples/helloworld/Makefile`、`sysdrv/drv_ko/examples/helloworld/README.md`
- **关联计划**：[`docs/superpowers/plans/2026-08-26-luckfox-external-kernel-module-helloworld.md`](../plans/2026-08-26-luckfox-external-kernel-module-helloworld.md)

---

## 1. 概述

本设计在 `sysdrv/drv_ko/examples/helloworld/` 增加一个最小 Linux 外置内核模块例程，用于演示如何基于当前 Luckfox Pico SDK 的 Linux 5.10.160 内核源码、内核构建产物与内置 ARM 交叉工具链生成 `.ko`，再将模块传到 Luckfox Pico Ultra W 开发板执行加载、日志检查与卸载。

例程定位为**按需手工构建的教学材料**，不是产品固件依赖。它不接入现有 `drv_ko` 自动构建和 OEM 打包链路，不会随 `./build.sh` 自动进入固件，也不会出现在板端 `/oem/usr/ko`；使用者需要在 Linux 编译机上显式执行例程 Makefile，并自行将生成的 `helloworld.ko` 传到开发板验证。

## 2. 背景与仓库现状

### 2.1 官方教程的能力边界

Luckfox Wiki 的[“Linux 下加载 ko 驱动模块”](https://wiki.luckfox.com/zh/Luckfox-Pico-RV1106/SDK/Kernel-Configuration/#6-linux%E4%B8%8B%E5%8A%A0%E8%BD%BDko%E9%A9%B1%E5%8A%A8%E6%A8%A1%E5%9D%97)章节提供了 [`ko.zip`](https://files.luckfox.com/wiki/Luckfox/Luckfox%20Pico%20PI/ko.zip)。压缩包内只有 `ko/Makefile` 与 `ko/helloworld.c` 两个文件；教程证明了 Kbuild 外置模块的基本路径，但 Makefile 把 SDK 内核和工具链前缀硬编码为 `/home/ubuntu/Luckfox/sdk-1015/luckfox-pico`，复制到其他 SDK 路径后不能直接使用，也没有解释编译机与开发板的职责边界、内核 ABI 匹配或构建前置条件。

2026-08-26 重新下载的官方文件基线如下，后续设计均以这两个原始文件为比较对象：

| 原始文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ko/Makefile` | 548 | `c99e6f79ba455b245c5873699f755fd526687b4159f7f69988d90865a890763e` |
| `ko/helloworld.c` | 337 | `360e744ec4fcb88f51d46873c4efeda12b3023317dca10a179509ffd16f2265d` |

#### 2.1.1 官方原始 `ko/Makefile`

以下内容逐字来自官方 zip；配方行保留 Makefile 必需的 Tab 缩进：

```make
obj-m += helloworld.o
KDIR:=/home/ubuntu/Luckfox/sdk-1015/luckfox-pico/sysdrv/source/kernel
PWD?=$(shell pwd)
MAKE := make
ARCH := arm
CROSS_COMPILE := /home/ubuntu/Luckfox/sdk-1015/luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-
KBUILD_OUTPUT := $(abspath $(dir $(lastword $(KDIR))))/objs_kernel
all:
	$(MAKE) O=$(KBUILD_OUTPUT) -C $(KDIR) M=$(PWD) modules \
ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE)
	echo $(PWD)
clean:
	rm -f *.ko *.o *.mod *.mod.o *.mod.c *.symvers *.order
```

#### 2.1.2 官方原始 `ko/helloworld.c`

以下内容逐字来自官方 zip：

```c
#include <linux/module.h>
#include <linux/init.h>

static int helloworld_init(void)
{
    printk("helloworld!\n");
    return 0;
}

static void helloworld_exit(void)
{
    printk("helloworld bye\n");
}

module_init(helloworld_init);
module_exit(helloworld_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Luckfox");
MODULE_VERSION("V1.0");
```

### 2.2 现有 `drv_ko` 自动构建与打包链路

`sysdrv/drv_ko/Makefile` 当前只遍历 `M_DIRS := rockit kmpp wifi motor`。这些正式组件构建后汇总到驱动 staging 目录，项目打包阶段再将 `kernel_drv_ko` 复制到 OEM 包目录的 `usr/ko`；生成 `oem.img` 后，目标系统以 `/oem` 挂载该分区，最终表现为板端 `/oem/usr/ko`。

```text
sysdrv/drv_ko/{rockit,kmpp,wifi,motor}
                    │ 父级 Makefile 汇总
                    ▼
output/out/sysdrv_out/kernel_drv_ko
                    │ project/build.sh::__PACKAGE_RESOURCES
                    ▼
output/out/oem/usr/ko
                    │ 打包 oem.img 并在目标系统挂载 /oem
                    ▼
开发板 /oem/usr/ko
```

`output/out/sysdrv_out/kernel_drv_ko` 是 SDK 构建过程中的模块 staging 目录，`output/out/oem/usr/ko` 是待制作 OEM 分区镜像的文件树，两者不是按模块类型划分的两个来源目录。一个 `.ko` 是否进入这些目录取决于构建和复制规则，而不是它采用了不同的内核模块格式。

### 2.3 `release_*` 目录不适用于本例程

`rockit` 与 `kmpp` 采用厂商包发布机制：`release_<包名>_<芯片>_<架构>` 保存预编译 `.ko` 等二进制发布物，带 `_asm` 的对应目录保存可重新参与链接的反汇编 `.S` 和 Makefile。父级构建在完整源码目录不存在时回退到这些发布包，因此 `release_rockit-ko_rv1106_arm` 与 `release_rockit-ko_rv1106_arm_asm` 描述的是厂商闭源/预编译交付形态，而不是所有外置模块的目录规范。

`helloworld` 是仓库内可读、可直接由单个 C 源文件构建的教学例程，不需要 `release_$(PKG_NAME)_$(CHIP)_$(ARCH)` 目录，也不产生源码版与发布版两套树。

## 3. 目标与非目标

### 3.1 目标

1. 给首次接触 Make/Kbuild 的使用者提供一个可读、可移植、错误信息明确的最小外置内核模块例程。
2. 默认从例程所在位置推导 SDK 根目录，消除官方 Makefile 的 `/home/...` 硬编码，同时允许高级使用者覆盖所有关键路径和架构参数。
3. 明确区分 Linux 编译机上的内核准备/模块构建步骤与 ARM 开发板上的模块加载/卸载步骤。
4. 在 Luckfox Pico Ultra W 上以 `insmod → /proc/modules + dmesg → rmmod → /proc/modules + dmesg` 完成端到端验收，并核对模块 `vermagic` 与正在运行的内核一致。
5. 保持教学例程与产品固件自动构建、打包和启动流程解耦。

### 3.2 非目标

- 不修改 `sysdrv/drv_ko/Makefile` 或它的 `M_DIRS`。
- 不让 `./build.sh`、`./build.sh driver` 或完整固件构建自动编译该例程。
- 不把 `helloworld.ko` 自动复制到 `kernel_drv_ko`、OEM 文件树或板端 `/oem/usr/ko`。
- 不增加开机自动加载脚本、设备树节点、Kconfig、内核 defconfig 或内核内建驱动。
- 不创建 `release_*` 发布包。
- 不提交任何 Kbuild 生成物。
- 不在本阶段修改另一个 `luckfox_pico_lvgl_example` 仓库或它的 Cloud Agent 配置。
- 不修改官方原始文件基线；仓库新增的派生 `helloworld.c` 与 Makefile 使用 `GPL-2.0-only` SPDX 文件头，运行时模块许可继续由 `MODULE_LICENSE("GPL")` 声明，README 同时记录官方来源、原始文件哈希与规范化差异。

## 4. 位置与集成方案

| 方案 | 位置/做法 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- | --- |
| A | `sysdrv/drv_ko/examples/helloworld/`，独立手工构建 | 与外置驱动领域相邻；`examples` 明确教学属性；不会被误认为正式产品模块；以后可容纳更多互不相关的示例 | 使用者必须进入目录显式执行 `make` | **采用** |
| B | `sysdrv/drv_ko/helloworld/`，仍不改父级 Makefile | 路径短一层 | 与 `rockit/kmpp/wifi/motor` 等正式组件同级，容易让人误判为漏接 `M_DIRS` 的产品驱动；后续示例会继续挤占顶层命名空间 | 不采用 |
| C | 将 `helloworld` 加入 `M_DIRS` 并进入 OEM | 随 SDK 自动构建和打包 | 教学代码成为所有相关固件的组成部分，增加镜像内容和加载认知成本，与按需示例目标冲突 | 不采用 |
| D | 单独建立示例仓库 | 生命周期完全独立 | 与内核源码、工具链和 `objs_kernel` 的版本关系变得隐式，使用者更容易拿错 SDK/内核组合 | 不采用 |

多一层 `examples/` 的价值不是构建技术要求，而是仓库语义和扩展边界：顶层继续只放产品组件，所有教学内容集中在一个稳定命名空间；未来增加参数模块、字符设备或中断示例时，可以并列放置而无需再次讨论顶层目录归属。

## 5. 文件结构与职责

```text
sysdrv/drv_ko/examples/helloworld/
├── Makefile       # Kbuild 外置模块入口、可覆盖变量、前置检查、帮助与清理
├── README.md      # 中文教程：来源与许可、准备内核、编译、传输、加载、检查、卸载、排错
└── helloworld.c   # 最小模块：加载/卸载各输出一条内核日志
```

父目录 `sysdrv/drv_ko/.gitignore` 已递归忽略 `*.cmd`、`*.ko`、`*.mod`、`*.mod.c`、`*.mod.o`、`*.o`、`*Module.symvers` 与 `*modules.order`，因此例程目录不新增重复 `.gitignore`。验收仍需用 `git status --short -- sysdrv/drv_ko/examples/helloworld/` 确认没有其他未忽略生成物。

## 6. 模块源码设计

仓库实现以 §2.1.2 内嵌的官方原始 `ko/helloworld.c` 为唯一完整源码基线，不在 spec 中重复粘贴第二份完整 C 文件。规范化版本保持官方行为和既有元数据，按下表执行确定性改写：

| 原始写法 | 计划写法 | 理由 |
| --- | --- | --- |
| 无文件级许可证标识 | 文件首行增加 `// SPDX-License-Identifier: GPL-2.0-only` | 对仓库派生源码使用不扩张到“or later”的 GPL v2 精确表达；`MODULE_LICENSE` 不能替代文件级许可证 |
| `static int helloworld_init(void)` | `static int __init helloworld_init(void)` | 使用内核初始化段标记，与官方教程对加载函数的说明一致 |
| `printk("helloworld!\n")` | `pr_info("helloworld!\n")` | 显式使用 info 级别日志接口，保留原日志文本 |
| `static void helloworld_exit(void)` | `static void __exit helloworld_exit(void)` | 使用内核退出段标记，与官方教程对卸载函数的说明一致 |
| `printk("helloworld bye\n")` | `pr_info("helloworld bye\n")` | 显式使用 info 级别日志接口，保留原日志文本 |
| 无描述字段 | 增加 `MODULE_DESCRIPTION("Luckfox Pico external kernel module example")` | 让模块元数据说明教学用途 |

`module_init(helloworld_init)`、`module_exit(helloworld_exit)`、`MODULE_LICENSE("GPL")`、`MODULE_AUTHOR("Luckfox")` 与 `MODULE_VERSION("V1.0")` 原样保留；头文件只需继续包含 `<linux/init.h>` 与 `<linux/module.h>`，排列顺序不构成行为契约。README 必须将实现描述为基于官方样例的派生版本，引用 §2.1 的下载地址与哈希，并分别列出本节的源码差异和 §7 的 Makefile 重构边界。

行为契约：

- `insmod helloworld.ko` 成功返回 0，并向内核日志写入 `helloworld!`。
- 模块名为 `helloworld`，加载后可通过 `/proc/modules` 查询；`lsmod` 是读取该模块表的等价用户接口。
- `rmmod helloworld` 或目标 BusyBox 已验证支持的 `rmmod helloworld.ko` 成功返回 0，并向内核日志写入 `helloworld bye`。
- 模块不创建设备节点、sysfs 属性、线程、中断、内存映射或其他持久状态。

## 7. Makefile 接口

例程只保留一个 Makefile，并使用本仓 Linux 5.10 外置模块文档所示的 `KERNELRELEASE` 双阶段结构，避免普通包装目标参与 Kbuild 的第二次解析：

```make
# SPDX-License-Identifier: GPL-2.0-only
ifneq ($(KERNELRELEASE),)
obj-m := helloworld.o
else
# 可覆盖变量、.PHONY、check-paths 与 all/prepare/clean/help 只定义在普通 Make 阶段
endif
```

Kbuild 阶段只声明 `obj-m := helloworld.o`；普通 Make 阶段才定义默认变量、`.PHONY` 和四个公开目标，并把 `all` 定义为第一个普通目标，由 GNU Make 将其选为默认目标。这样直接执行 `make` 时由包装目标调用内核 Kbuild，而 Kbuild 重新读取同一文件时不会引入包装规则或发生目标名冲突。

### 7.1 可覆盖变量

| 变量 | 默认值/推导 | 含义 |
| --- | --- | --- |
| `SDK_ROOT` | 从 `sysdrv/drv_ko/examples/helloworld/` 向上四级得到仓库根目录 | Luckfox Pico SDK 根目录 |
| `KDIR` | `$(SDK_ROOT)/sysdrv/source/kernel` | Linux 内核源码目录，传给 Kbuild 的 `-C` |
| `KBUILD_OUTPUT` | `$(SDK_ROOT)/sysdrv/source/objs_kernel` | 与目标板配置匹配的内核输出目录，传给 Kbuild 的 `O=` |
| `ARCH` | `arm` | 目标内核架构 |
| `CROSS_COMPILE` | `$(SDK_ROOT)/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/arm-rockchip830-linux-uclibcgnueabihf-` | 工具链命令前缀；可使用完整路径前缀或 PATH 中的命令前缀，Kbuild 会在其后追加 `gcc`、`ld` 等工具名 |

所有变量使用 Make 的条件赋值，调用者可在命令行覆盖，例如 `make SDK_ROOT=/workspace/luckfox-pico` 或 `make KBUILD_OUTPUT=/path/to/matching/objs_kernel`。命令行赋值优先于 Makefile 默认值，不依赖用户提前导出环境变量；同名环境变量可作为输入，但 README 统一推荐显式命令行覆盖，便于复现。

路径可变不等于支持空白字符：本仓 Linux 5.10 顶层 Kbuild 会按 Make 单词拆分 `M=`，并把含空白的外置模块路径判定为同时构建多个模块目录。`$(CURDIR)`、`SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT` 与 `CROSS_COMPILE` 的路径部分都不得包含空白字符；内部 `check-paths` 目标必须让 `prepare` 与 `clean` 在调用 Kbuild 前给出一致的明确诊断。README 的示例路径同样遵守这一约束，不把增加 shell 引号描述为可解决 Kbuild 的 `M=` 限制。

### 7.2 公开目标

| 目标 | 行为 |
| --- | --- |
| `all` | 第一个普通目标，因此是默认目标；先执行 `prepare`，再调用 `$(MAKE) -C $(KDIR) O=$(KBUILD_OUTPUT) M=$(CURDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules` |
| `prepare` | 只检查前置条件并给出可操作的错误信息，不自动编译完整内核 |
| `clean` | 先执行共享的空白路径检查，再通过 Kbuild 清理由本例程生成的文件；即使模块尚未成功构建，也应可重复执行且不依赖完整工具链或内核产物检查 |
| `help` | 显示目标、变量、当前解析值、最小构建示例和“必须匹配运行内核”的提示；不要求内核输出已准备好 |

Makefile 首行使用 `# SPDX-License-Identifier: GPL-2.0-only`，普通 Make 分支将 `all` 放在第一个普通目标的位置，使 GNU Make 在直接调用时选择它作为默认入口；不设置显式默认目标，避免干扰 Kbuild 在 `include/config/kernel.release` 为空时执行外置模块清理。`.PHONY: all prepare clean help check-paths` 声明四个公开目标和一个内部路径检查目标，避免同名文件或目录使操作型目标被错误判定为已经完成。`prepare` 与 `clean` 都依赖 `check-paths`；`clean` 不依赖其余主机、工具链或内核输出检查。

`prepare` 固定执行七项教学护栏：

1. `$(CURDIR)`、`SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT` 与 `CROSS_COMPILE` 的路径部分不得包含空白字符；该项由共享的 `check-paths` 执行。
2. `uname -s` 必须为 `Linux`；macOS 不能原生执行仓库内 Linux ELF 工具链。
3. `uname -m` 必须为 `x86_64`；ARM 开发板和原生 ARM64 Linux 环境不属于支持路径。
4. `$(CROSS_COMPILE)gcc` 必须存在且可调用；带目录分隔符时检查对应可执行文件，不带目录分隔符时通过 PATH 查找命令。
5. `$(KBUILD_OUTPUT)/.config` 必须存在且非空，表明已为目标板生成有效内核配置。
6. `$(KBUILD_OUTPUT)/scripts/module.lds` 必须存在且非空，表明外置模块所需的内核构建准备已完成。
7. `$(KBUILD_OUTPUT)/Module.symvers` 必须存在且非空，表明 modpost 可以读取当前内核及其已构建模块的导出符号表并执行 unresolved symbol 检查。

这些检查是面向初学者的错误前移，不是对所有 Kbuild 项目的普遍强制规范。当前内核未启用 `CONFIG_MODVERSIONS`，因此 `Module.symvers` 中导出符号的 CRC 为零，但 modpost 仍依靠该文件确认模块引用的内核符号存在；缺失时 unresolved symbol 检查会整体跳过。正式验收只接受同一次 kernel-only 构建产生的完整 `objs_kernel`，不提供仅经 `modules_prepare` 且缺少 `Module.symvers` 的降级验收路径。`CONFIG_MODULES` 无需在例程中重复检查：Ultra W defconfig 已启用它，而内核 Kbuild 对禁用模块的配置已有明确错误和非零退出码。

## 8. 构建环境与数据流

### 8.1 支持环境

- **Cursor Cloud Agent**：使用 linux/amd64 运行当前仓库 `.cursor/Dockerfile` 定义的 Ubuntu 24.04 环境，不使用 Docker-in-Docker；SDK 工作区路径可变，由 Makefile 相对推导。
- **通用 Ubuntu 24.04 Docker/远程编译机**：主机或容器必须是 linux/amd64；从当前 `.cursor/Dockerfile` 构建镜像时显式指定 `--platform=linux/amd64`，将 SDK 挂载到 `/workspace/luckfox-pico` 并在该目录工作。ARM64 Docker 主机只有在启用 amd64 仿真且显式选择该平台时才属于支持路径。
- **远程仓库与 SSH 参数**：远程验证直接在 `/data/luckfox-pico` 切换到 `codex/helloworld-kernel-module-example`，不创建额外 worktree；切换前只允许恢复 AGENTS.md 已登记的三个可再生 Wi-Fi 二进制，发现其他改动必须停止。SSH 端口只从 macOS 控制机环境变量 `LUCKFOX_SSH_PORT` 读取，仓库文档、命令和提交均不记录具体端口值。
- **不支持 macOS 原生编译**：内置交叉工具链是 x86-64 Linux ELF；macOS 作为控制机负责编辑、Git、从 Linux 编译机取得产物、SHA-256 校验、ADB/串口和板端验收。
- **不建议开发板本机构建**：开发板是 ARM 目标机，不能执行 SDK 内置的 x86-64 Linux 交叉工具链，资源也不适合承载完整 SDK 内核构建。

远程容器允许未来采用以下并列多仓布局，但本设计只挂载和使用 SDK 仓库，不修改 LVGL 仓库：

```text
/workspace/
├── luckfox-pico/
└── luckfox_pico_lvgl_example/   # 未来可选，另立 Cloud Agent 设计
```

### 8.2 内核准备

Ultra W 的可复现准备路径固定为：

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

test -s "$KBUILD_OUTPUT/.config"
test -s "$KBUILD_OUTPUT/scripts/module.lds"
test -s "$KBUILD_OUTPUT/Module.symvers"
```

`lunch` 选择 `RV1106_Luckfox_Pico_Ultra`、EMMC、Buildroot，`./build.sh kernel` 生成与目标固件匹配的 `.config`、DTB、内核镜像和基础输出；由于当前 `O=sysdrv/source/objs_kernel` 的 out-of-tree `%.img` 路径不会执行 `modules`，必须随后显式构建内核 `modules` 目标，才能得到外置模块所需的 `scripts/module.lds` 和完整 `Module.symvers`。三个 `test -s` 全部成功才表示内核输出准备完成；该路径不要求耗时数小时的完整 rootfs/固件重建。

### 8.3 模块构建与板端验证

```text
linux/amd64 Ubuntu 24.04 编译机       macOS 控制机                    Luckfox Pico Ultra W
──────────────────────────────       ────────────                    ─────────────────────
kernel 源码 + objs_kernel + 工具链
             │ make
             ▼
      helloworld.ko + SHA-256
             │ 文件下载或 SCP
             └──────────────────────▶ 校验编译机 SHA-256
                                             │ adb push
                                             └──────────────────────▶ /tmp/helloworld.ko
                                                                          │ 校验板端 SHA-256
                                                                          │ insmod + /proc/modules + dmesg
                                                                          │ rmmod / dmesg
                                                                          ▼
                                                                       验收完成
```

README 以“linux/amd64 编译机生成产物、macOS 控制机通过 ADB 操作 USB 直连开发板”为主路径，必须给出编译机、macOS 和板端三处命令及两次传输后的 SHA-256 对照。只有当远程编译机能够访问开发板网络时，才允许将“编译机通过 SCP 直接传到板端 `/tmp`”作为可选路径；该路径仍需校验传输前后 SHA-256。所有路径都把模块放在 `/tmp`，避免让教学验证看起来像 OEM 固件安装。

## 9. 内核版本匹配

外置模块不是只按源码 API 兼容；内核会比较模块 `vermagic`，并可能受配置、符号布局和 `CONFIG_MODVERSIONS` 影响。例程必须针对开发板正在运行的同一内核源码、目标板 `.config` 和对应 `objs_kernel` 构建。

README 的验收前检查固定为 release 初筛和模块元数据检查，不把它表述为完整 ABI 证明：

```bash
# 编译机
readelf -p .modinfo helloworld.ko | grep -E 'vermagic|license|author|description|version|name'

# 开发板
uname -r
strings /tmp/helloworld.ko | grep '^vermagic='
```

`uname -r` 只能与模块 `vermagic` 的 `UTS_RELEASE` 部分做初筛；`SMP`、`preempt`、`mod_unload`、`modversions`、架构标记等完整字段由运行内核的模块加载器校验。完整 ABI 验收以 `insmod` 返回值和紧随其后的 `dmesg` 为权威依据。若固件来源能够保证当前 `/oem/usr/ko` 与正在运行的 `boot.img` 配套，可选取一个板载 `.ko` 对照完整 `vermagic`，但不得把来源不明或可能与 boot 不同步的 OEM 模块设为硬性前置条件。

若 `insmod` 报 `Invalid module format`，第一排查项是紧随其后的 `dmesg` 中的版本魔数差异，而不是反复执行 `insmod -f`。例程不教授强制绕过 ABI 检查。

更新内核时通常需要烧录包含 kernel/DTB 的 `boot` 分区，但能否只烧 `boot.img` 取决于改动是否同时影响模块、rootfs、OEM 或板级配置；本例程不把“更新内核永远只需烧 boot”表述为通用结论。

## 10. 验证设计与验收标准

### 10.1 Makefile 静态与负向验证

1. `make help` 在未准备 `objs_kernel` 时仍成功并显示全部目标和变量。
2. 非 Linux 主机和 `uname -m` 不为 `x86_64` 的 Linux 主机执行 `make prepare` 时分别得到明确诊断。
3. 让例程目录或任一可覆盖路径包含空白字符，确认 `make prepare` 在调用 Kbuild 前说明该路径不受支持，并确认 `make clean` 对例程目录空白给出同一诊断。
4. 分别让交叉编译器缺失，以及让 `.config`、`scripts/module.lds`、`Module.symvers` 缺失或为零字节，确认每种失败都有唯一、可操作的诊断，且不会触发内核全量构建。
5. 从默认目录执行、显式覆盖 `SDK_ROOT`/`KBUILD_OUTPUT` 执行以及将工具链目录加入 PATH 后使用裸 `CROSS_COMPILE` 前缀执行，都解析到预期路径并成功完成 `prepare` 与模块构建。
6. `make clean` 可重复执行，清理后仓库路径下没有未忽略生成物；在独立临时例程目录完成普通 `make` 后，将空文件只读绑定到 `$(KBUILD_OUTPUT)/include/config/kernel.release`，`make clean` 仍须返回 0 并清除全部 Kbuild 产物。

### 10.2 linux/amd64 Ubuntu 24.04 构建验收

1. 从当前 `.cursor/Dockerfile` 的 linux/amd64 环境完成 Ultra W 的 `lunch`、`./build.sh kernel` 和显式内核 `modules` 构建，并确认 `.config`、`scripts/module.lds`、`Module.symvers` 均存在且非空。
2. 例程 `make` 返回 0，生成文件被 `file` 识别为 ARM EABI5 relocatable ELF。
3. 模块元数据包含 `license=GPL`、`author=Luckfox`、`description=Luckfox Pico external kernel module example`、`version=V1.0`、`name=helloworld`，且 `vermagic` 的 release 部分与板端 `uname -r` 一致。
4. `$(KBUILD_OUTPUT)/Module.symvers` 存在，构建日志没有缺失符号表警告、unresolved symbol、编译错误或链接错误。

### 10.3 Ultra W 板端验收

1. 编译机原始文件、macOS 控制机取得的文件和板端 `/tmp/helloworld.ko` 三者 SHA-256 一致；若采用编译机直传板端的可选路径，则传输两端 SHA-256 一致。
2. `insmod /tmp/helloworld.ko` 返回 0。
3. `/proc/modules` 出现 `helloworld`，引用计数为 0。
4. `dmesg` 出现一条新的 `helloworld!`。
5. `rmmod helloworld` 返回 0，随后 `/proc/modules` 不再出现该模块。
6. `dmesg` 出现一条新的 `helloworld bye`。
7. 验证结束后删除板端临时 `.ko`；不改写 `/oem/usr/ko`。

### 10.4 实施验收证据

验收对象为本 PR 中的模块源码与 Makefile，构建环境为当前 `.cursor/Dockerfile` 生成的 linux/amd64 Ubuntu 24.04 镜像 `sha256:176845c9591d95293ba0cba8da38774cb9b453b2c5653bcd33e058a8ca9d2bee`。默认完整路径与 PATH 裸前缀构建均生成 SHA-256 为 `c3f48770f72f08980cd8f24bb296010f0c55060075bb00ca5f261704850fdb68` 的同一模块；该产物已完成三端传输及 Ultra W 生命周期验收。验证证据锚定构建镜像、模块摘要与板端实测值，不绑定 Git 对象标识。标准镜像构建成功，未使用代理回退。

| 验收项 | 实测结果 |
| --- | --- |
| 内核输出准备 | `.config` 150,834 B、`scripts/module.lds` 977 B、`Module.symvers` 616,577 B；三者均存在且非零字节 |
| Makefile 正向路径 | `make help`、默认 `make prepare`、显式覆盖 `SDK_ROOT`/`KBUILD_OUTPUT` 的 `prepare` 与构建、PATH 中裸 `CROSS_COMPILE` 前缀的 `prepare` 与构建、最终默认 `make` 均返回 0 |
| 七类前置检查 | 路径空白、主机 OS、主机架构、交叉编译器、`.config`、`scripts/module.lds`、`Module.symvers` 七类检查均命中各自唯一诊断；后三项的缺失与零字节场景均被拒绝；路径类覆盖 `CURDIR`、`SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT`、`CROSS_COMPILE`，且 `prepare`/`clean` 对空白 `CURDIR` 诊断一致 |
| 重复清理与构建日志 | 连续两次 `make clean` 均返回 0，清理后顶层 Kbuild 生成物查找为空；独立临时例程目录中普通 `make` 生成 13 个顶层 Kbuild 产物，正常 `make clean` 后为 0，再次普通 `make` 后以空文件只读绑定 `include/config/kernel.release`，`make clean` 返回 0 且产物由 13 个清为 0；最终构建日志无缺失 `Module.symvers`、unresolved symbol、modpost、编译或链接错误 |
| 模块文件 | 79,332 B；`ELF 32-bit LSB relocatable, ARM, EABI5 version 1 (SYSV), BuildID[sha1]=e4558203df338d4f26eee776bffa7d96c598846a, with debug_info, not stripped` |
| 模块摘要与 ABI 初筛 | SHA-256 `c3f48770f72f08980cd8f24bb296010f0c55060075bb00ca5f261704850fdb68`；完整 `vermagic=5.10.160 mod_unload ARMv7 thumb2 p2v8`，与板端 `uname -r` 的 `5.10.160` release 一致 |
| 模块元数据 | `license=GPL`、`author=Luckfox`、`description=Luckfox Pico external kernel module example`、`version=V1.0`、`name=helloworld`、`vermagic=` 六项分别存在 |
| 三端传输完整性 | 远程编译机、macOS `/tmp/helloworld.ko`、开发板 `/tmp/helloworld.ko` 的 SHA-256 均为 `c3f48770f72f08980cd8f24bb296010f0c55060075bb00ca5f261704850fdb68` |
| Ultra W 加载 | 板端实测 `insmod` 返回 0；`/proc/modules` 为 `helloworld 827 0`，引用计数为 0；`helloworld!` 计数由 3 增至 4，恰新增一条 |
| Ultra W 卸载 | 板端实测 `rmmod` 返回 0；随后 `/proc/modules` 无 `helloworld`；`helloworld bye` 计数由 3 增至 4，恰新增一条 |
| 最终清理 | 板端与 macOS 的 `/tmp/helloworld.ko` 均不存在，模块保持未加载，未写入 `/oem/usr/ko` |

### 10.5 既有参考可行性证据

官方原始样例已基于 Linux 5.10.160 构建产物完成一次端到端验证；该证据只证明官方基线和总体工具链路径可行，规范化源码仍须按 §10.1–§10.3 重新验收：

| 项目 | 实测值 |
| --- | --- |
| 文件类型 | `ELF 32-bit LSB relocatable, ARM, EABI5` |
| 文件大小 | `78,464 B` |
| SHA-256 | `cae073ff877331206c9139dac58efce8aa3e3987bb3e1a97e7a4c7dd83552c72` |
| vermagic | `5.10.160 mod_unload ARMv7 thumb2 p2v8` |
| 加载 | `insmod_rc=0`，`lsmod` 为 `helloworld 929 0` |
| 加载日志 | `helloworld!` |
| 卸载 | `rmmod_rc=0`，模块随后不在 `lsmod` 中 |
| 卸载日志 | `helloworld bye` |

## 11. 风险与约束

- **ABI 错配**：最常见结果是 `Invalid module format`；通过同一板型完整内核构建产物、release 初筛以及板端 `insmod` 返回值和即时 `dmesg` 控制，来源可靠的板载 `.ko` 完整 `vermagic` 只作可选对照。
- **内核输出不完整**：只有源码和 `.config` 不足以稳定构建外置模块；`scripts/module.lds` 等生成文件必须来自内核准备/构建步骤。
- **误入产品链路**：若未来有人把 `examples` 加入 `M_DIRS`，例程可能进入 OEM；README 与父级集成边界必须保持明确，当前不增加自动化复制规则。
- **生成物污染**：远程验证结束后允许工作目录保留被 `.gitignore` 覆盖的 Kbuild 生成物，本设计只要求它们不被 Git 跟踪、暂存或提交；实现验收必须用 `git ls-files` 与 cached diff 明确检查，不能以普通 `git status` 无输出替代。
- **支持环境漂移**：本设计只承诺当前 `.cursor/Dockerfile` 的 linux/amd64 Ubuntu 24.04 路径；若切换 CPU 架构、基础镜像或 SDK 内核版本，必须重跑完整构建与板端验收。
- **macOS 大小写冲突**：仓库含 21 对仅大小写不同的跟踪路径，默认不区分大小写的 APFS 无法完整检出，可能让工作树持续显示修改并阻止 `pull --rebase`；日常解决方案见 §12 Q13。
- **示例许可表达**：官方样例以 `MODULE_LICENSE("GPL")` 表达 GPL v2，但未区分 only/or-later，Makefile 也没有文件级标识；仓库派生文件统一采用保守的 `GPL-2.0-only` SPDX 表达，并保留官方来源、原始哈希与规范化差异，不把 `MODULE_LICENSE` 当作 SPDX 的替代品。

## 12. QA（设计决策与约束澄清）

本节集中记录正文未完整展开的设计决策与约束；已被正文吸收的主题只保留结论与指针，不重复完整论证。

**Q1：例程应提交到当前 SDK 仓库还是单独仓库，具体放在哪里？**

A：提交到当前 SDK 仓库的 `sysdrv/drv_ko/examples/helloworld/`；它依赖本仓内核、`objs_kernel` 与工具链，`examples` 同时把教学代码和正式组件分层，详见 §4–§5。

**Q2：为什么不放在 `sysdrv/drv_ko/helloworld/`，也不采用 `release_$(PKG_NAME)_$(CHIP)_$(ARCH)`？**

A：顶层目录用于 `rockit/kmpp/wifi/motor` 等产品组件，`release_*` 是厂商二进制/反汇编发布机制；本例程是完整可读源码且不进入产品链路，详见 §2.3 与 §4。

**Q3：官方 zip 与仓库实现是什么关系，源码是否原样复制？**

A：§2.1 完整内嵌并以哈希固定官方 `ko/Makefile` 和 `ko/helloworld.c`；仓库源码保留行为及官方模块声明，但规范化为 `__init`/`__exit`、`pr_info` 并增加 `MODULE_DESCRIPTION`，Makefile 则从固定绝对路径脚本重构为相对默认路径、可覆盖变量、前置检查及 `clean`/`help` 目标完整的双阶段入口，详见 §6–§7。

**Q4：是否为 `helloworld.c` 增加 SPDX？**

A：增加。仓库派生的 `helloworld.c` 使用 `// SPDX-License-Identifier: GPL-2.0-only`，Makefile 使用对应的 `#` 注释形式；保留官方 `MODULE_LICENSE("GPL")`、作者声明、来源、原始哈希与规范化差异，详见 §3.2、§6–§7 与 §11。

**Q5：Makefile 应提供哪些入口和可覆盖参数？**

A：单个 Makefile 以 `KERNELRELEASE` 区分两次解析：Kbuild 分支只定义 `obj-m := helloworld.o`，普通分支将 `all` 定义为第一个普通目标，由 GNU Make 将其作为默认入口，并继续定义 `prepare`、`clean`、`help`；不设置显式默认目标，以免干扰 Kbuild 的外置模块清理。内部 `check-paths` 统一 `prepare` 与 `clean` 的空白路径诊断；变量固定为 `SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT`、`ARCH`、`CROSS_COMPILE`，默认值相对推导且可由命令行覆盖，详见 §7。

**Q6：为什么 `prepare` 增加七项检查，是否必须检查 `Module.symvers`？**

A：`prepare` 固定检查路径无空白、Linux 操作系统、x86-64 主机、交叉编译器、`.config`、`scripts/module.lds` 与 `Module.symvers`，其中空白路径检查由 `prepare`/`clean` 共享。虽然当前未启用 `CONFIG_MODVERSIONS`，modpost 仍需要 `Module.symvers` 检查内核导出符号；正式验收只接受 `./build.sh kernel` 后显式构建 `modules` 得到的完整产物，详见 §7.2 与 §8.2。

**Q7：不修改父级 `sysdrv/drv_ko/Makefile` 时，使用者如何构建和使用，`.ko` 为什么不会进入 `/oem/usr/ko`？**

A：使用者进入例程目录显式执行 `make`；主路径先把 `.ko` 从 linux/amd64 编译机传到 macOS 控制机并校验 SHA-256，再通过 ADB 推到板端 `/tmp` 并再次校验。未加入 `M_DIRS` 就不会进入 `kernel_drv_ko → OEM 文件树 → oem.img` 链路，详见 §2.2、§3.2 与 §8.3。

**Q8：README 面向谁、使用什么语言？**

A：面向首次接触 Make/Kbuild 的使用者，正文以中文为主，命令、变量、路径和内核技术字符串保持英文；必须区分 linux/amd64 编译机、macOS 控制机与开发板步骤，职责见 §3.1、§5 与 §8.3。

**Q9：在哪些机器上构建，是否需要全量固件编译？**

A：编译只支持当前 `.cursor/Dockerfile` 的 linux/amd64 Ubuntu 24.04 Cloud Agent 和同环境的 Docker/远程 Linux 主机，不采用官方 Ubuntu 22.04 容器；macOS 不原生编译，而是取得产物后负责 ADB/串口和板端验收，开发板只加载和卸载模块。远程验证直接切换 `/data/luckfox-pico` 到当前 `codex` 开发分支，不创建 worktree，SSH 端口由未入库的 `LUCKFOX_SSH_PORT` 提供。Linux 编译机只需执行 Ultra W 的 `lunch`、`./build.sh kernel` 和显式内核 `modules` 构建，无需全量固件构建，详见 §8.1–§8.3。

**Q10：验收做到哪一层？**

A：必须完成 Makefile 正/负向检查、linux/amd64 Ubuntu 24.04 ARM 模块构建与完整元数据核对、跨主机和板端 SHA-256 对照、release 初筛以及 Ultra W 板端 `insmod → /proc/modules + dmesg → rmmod → /proc/modules + dmesg` 全链路；完整 ABI 以模块加载器结果为准，详见 §9–§10。

**Q11：未来 LVGL 多仓环境是否纳入本设计？**

A：本 spec 只保留 `/workspace` 并列仓库的兼容约束，不修改 `luckfox_pico_lvgl_example` 或其 Cloud Agent；跨仓 SDK 获取方式另立 spec，详见 §3.2 与 §8.1。

**Q12：本次如何交付和合并？**

A：使用 `codex/` 开发分支和 base=`dev` 的 PR；例程、最终 Design Spec 与 Implementation Plan 均位于该 PR，Review 与合并由维护者负责，详见 §13。

**Q13：为什么默认 macOS 工作树可能长期显示 netfilter 等文件被修改，并导致 `git pull --rebase` 无法开始？**

A：仓库跟踪了 21 对仅大小写不同但内容不同的路径，例如 `xt_connmark.h` 与 `xt_CONNMARK.h`；默认不区分大小写的 APFS 会把每对名称映射到同一物理文件，本地实测两者 inode 相同，而 Git tree 中对应不同 blob。`core.ignorecase=false` 只能改变 Git 的名称判断，不能增加文件系统表达能力，`--autostash`、`reset` 或反复 checkout 还可能只切换“哪一个大小写变体看起来被修改”。推荐把仓库重新克隆到区分大小写的 APFS 卷/磁盘映像，或在 Linux、远程编译机等区分大小写的文件系统中执行 pull、rebase 与构建；迁移前先保存真实业务改动，不要批量恢复这些冲突路径。若只是自动化重写少量已知提交且不能迁移，可使用独立临时 index 构造提交，但这只是受控维护手段，不是日常 `git pull --rebase` 的替代方案。

## 13. 交付与 Review 门

1. Design Spec、Implementation Plan 与三个例程文件均交付到以 `dev` 为 base 的 PR #7，功能提交在前，最终文档提交在后。
2. 当前实现已通过 §10.4 的构建、传输和板端验收；Kbuild 生成物不被 Git 跟踪、暂存或提交。
3. 后续若改变内核、板型、构建镜像、例程接口或集成边界，必须更新当前 spec/plan 并重跑受影响验收。
4. Review 与合并由维护者负责，自动化代理不得合并到 `dev`。

## 14. 参考资料

- [Luckfox Wiki：内核配置——6. Linux 下加载 ko 驱动模块](https://wiki.luckfox.com/zh/Luckfox-Pico-RV1106/SDK/Kernel-Configuration/#6-linux%E4%B8%8B%E5%8A%A0%E8%BD%BDko%E9%A9%B1%E5%8A%A8%E6%A8%A1%E5%9D%97)
- [Luckfox 官方 ko.zip](https://files.luckfox.com/wiki/Luckfox/Luckfox%20Pico%20PI/ko.zip)
- [Linux Kernel Documentation：Building External Modules](https://docs.kernel.org/kbuild/modules.html)
- [Linux Kernel Documentation：Linux kernel licensing rules](https://docs.kernel.org/process/license-rules.html)
- 仓库内 `sysdrv/drv_ko/Makefile`、`sysdrv/Makefile` 与 `project/build.sh` 的当前构建/打包规则
