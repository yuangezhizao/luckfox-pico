# HelloWorld 外置内核模块例程

本目录是 Luckfox Pico 的 Linux 外置内核模块例程，不是用户空间程序。它派生自 Luckfox 官方 [ko.zip](https://files.luckfox.com/wiki/Luckfox/Luckfox%20Pico%20PI/ko.zip) 的 `ko/Makefile` 与 `ko/helloworld.c`：官方 `ko/Makefile` 的 SHA-256 是 `c99e6f79ba455b245c5873699f755fd526687b4159f7f69988d90865a890763e`，官方 `ko/helloworld.c` 的 SHA-256 是 `360e744ec4fcb88f51d46873c4efeda12b3023317dca10a179509ffd16f2265d`。

仓库版本的 `helloworld.c` 相对官方源码增加 SPDX 标识、`__init`/`__exit` 段标记、`pr_info` 和 `MODULE_DESCRIPTION`；Makefile 则由固定 SDK 绝对路径的脚本重构为 `KERNELRELEASE` 双阶段入口，改用仓库相对默认路径并提供可覆盖变量、构建前置检查、重复清理与帮助目标。`helloworld!`、`helloworld bye` 两条日志文本以及 `GPL`、`Luckfox`、`V1.0` 官方模块元数据保持兼容。加载成功后模块名为 `helloworld`，`dmesg` 会新增 `helloworld!`；卸载后会新增 `helloworld bye`。它不创建设备节点、sysfs 属性、线程、中断、内存映射或其他持久状态。

本例程未加入父级 `M_DIRS`，因此不会由 `./build.sh` 自动构建，也不会进入 `/oem/usr/ko`。必须主动进入本目录运行 `make`，再将生成的 `.ko` 放到开发板的临时目录验证。

## 三处职责

1. linux/amd64 Ubuntu 24.04 编译机：选择 Ultra W、准备内核输出并交叉编译模块。
2. macOS 控制机：从编译机取得 `.ko`、核对 SHA-256，再通过 ADB 传到 USB 直连的开发板。
3. Luckfox Pico Ultra W：只负责 `insmod`、`lsmod`、`dmesg` 和 `rmmod`。

本文构建流程仅支持 linux/amd64 Ubuntu 24.04；其他系统或架构不在支持范围内。macOS 不能原生执行仓库内的 Linux x86-64 工具链；开发板是 ARM 目标机，也不能执行该工具链。若编译机是通过 SSH 访问的远程机器，远程仓库直接使用 `/data/luckfox-pico` 当前工作树，并将该工作树挂载到容器的 `/workspace/luckfox-pico`，不创建远程 worktree。后文的内核准备、模块构建和首次 SHA-256 均在这套容器内外映射中执行，产物因此位于用于 SCP 的 `/data/luckfox-pico` 路径。所有 SSH/SCP 连接前都先检查端口环境变量：

```bash
: "${LUCKFOX_SSH_PORT:?请先设置 LUCKFOX_SSH_PORT}"
```

## 在 linux/amd64 Ubuntu 24.04 编译机准备 Ultra W 内核

以下命令在远程当前工作树 `/data/luckfox-pico` 挂载到容器后的 `/workspace/luckfox-pico` 执行：

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

`lunch` 的三个选择依次是 `RV1106_Luckfox_Pico_Ultra`、EMMC、Buildroot。`./build.sh kernel` 会生成与目标固件匹配的 `.config`、DTB、`zImage`、`Image.gz` 和镜像，但当前 out-of-tree 输出模式不会自动执行 `modules`。因此它单独不足以准备外置模块；后续显式 `modules` 命令会生成所需的 `scripts/module.lds` 和完整 `Module.symvers`。

## 构建模块

```bash
cd /workspace/luckfox-pico/sysdrv/drv_ko/examples/helloworld
make
```

Makefile 对外提供以下目标：

| 目标 | 命令 | 用途 |
| --- | --- | --- |
| `all`（默认） | `make` 或 `make all` | 先执行 `prepare` 检查，再调用内核 Kbuild 构建 `helloworld.ko`。 |
| `prepare` | `make prepare` | 只检查路径、主机、交叉编译器及内核输出是否满足构建条件，不生成模块。 |
| `clean` | `make clean` | 调用内核 Kbuild 删除当前例程生成的 `.ko`、`.o`、`.cmd`、`Module.symvers`、`modules.order` 等文件。 |
| `help` | `make help` | 显示目标、当前变量值和基本示例；查看帮助不要求预先准备内核输出。 |

常用执行顺序如下：

```bash
make help
make prepare
make
make clean
```

`make` 的变量接口如下；命令行变量覆盖优先于 Makefile 默认值。

| 变量 | 含义 |
| --- | --- |
| `SDK_ROOT` | Luckfox Pico SDK 根目录，默认从本目录向上四级推导。 |
| `KDIR` | 内核源码目录，默认是 `$(SDK_ROOT)/sysdrv/source/kernel`，传给 Kbuild 的 `-C`。 |
| `KBUILD_OUTPUT` | 与目标板配置匹配的内核输出目录，默认是 `$(SDK_ROOT)/sysdrv/source/objs_kernel`，传给 Kbuild 的 `O=`。 |
| `ARCH` | 目标内核架构，默认是 `arm`。 |
| `CROSS_COMPILE` | 交叉工具链命令前缀；既可使用完整路径前缀，也可使用 PATH 中的命令前缀，Kbuild 会在后面追加 `gcc`、`ld` 等工具名。 |
| `M=$(CURDIR)` | 告诉 Kbuild 当前例程目录是需要构建的外置模块目录。 |

例如，可显式覆盖内核输出目录，或使用已加入 `PATH` 的交叉编译器前缀：

```bash
make KBUILD_OUTPUT=/path/to/matching/objs_kernel
make CROSS_COMPILE=arm-rockchip830-linux-uclibcgnueabihf-
```

多个变量可以在同一条命令中同时覆盖；`$(CURDIR)`、`SDK_ROOT`、`KDIR`、`KBUILD_OUTPUT` 和 `CROSS_COMPILE` 的路径部分均不得包含空白字符。

若 `make` 提示 `.config`、`scripts/module.lds` 或 `Module.symvers` 缺失或为空，请重新执行上一节对应的内核准备步骤。若 `insmod` 返回 `Invalid module format`，应立即查看紧随失败后的 `dmesg`，禁止使用 `insmod -f` 绕过检查。`uname -r` 只能初步核对 `vermagic` 的 release 部分；最终 ABI 判断以模块加载器和 `dmesg` 为准。

## 检查模块元数据与传输

先在编译机检查模块元数据和编译机原始文件的 SHA-256：

```bash
cd /workspace/luckfox-pico/sysdrv/drv_ko/examples/helloworld
readelf -p .modinfo helloworld.ko | grep -E 'vermagic|license|author|description|version|name'
sha256sum helloworld.ko
```

在 macOS 上，从远程编译机的当前工作树取得文件并核对第二份 SHA-256。远程编译机为 `mastodon.yuangezhizao.cn`：

```bash
: "${LUCKFOX_SSH_PORT:?请先设置 LUCKFOX_SSH_PORT}"
ssh -p "$LUCKFOX_SSH_PORT" root@mastodon.yuangezhizao.cn 'sha256sum /data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/helloworld.ko'
scp -P "$LUCKFOX_SSH_PORT" root@mastodon.yuangezhizao.cn:/data/luckfox-pico/sysdrv/drv_ko/examples/helloworld/helloworld.ko /tmp/helloworld.ko
shasum -a 256 /tmp/helloworld.ko
```

编译机的 SHA-256 与 macOS 的 SHA-256 必须完全相同。然后通过 ADB 将文件送到开发板，并核对第三份 SHA-256：

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

macOS 与开发板的 SHA-256 也必须完全相同，至此三处 SHA-256 一致。加载前，`vermagic=` 后的第一个字段必须与 `uname -r` 完全一致；该检查只能初步核对内核 release，最终 ABI 判断仍以模块加载器和 `dmesg` 为准。`insmod` 成功后，`lsmod` 应出现引用计数为 0 的 `helloworld`，`dmesg` 应出现新的 `helloworld!`；`rmmod helloworld` 成功后，`lsmod` 不应再出现该模块，`dmesg` 应出现新的 `helloworld bye`。全程只使用 `/tmp/helloworld.ko` 临时验证，不写入 `/oem/usr/ko`，也不配置自动加载。
