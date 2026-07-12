# AGENTS

## 交互约定

- 与本仓库交互时，请始终使用中文回复（代码、路径、命令除外）。

## Cursor Cloud specific instructions

> 说明：保留该英文章节标题作为工具约定锚点；下方内容使用中文。

本仓库是 **Luckfox Pico SDK**（V1.4）——基于 Rockchip 的嵌入式 Linux **交叉编译 SDK**，为 RV1103/RV1106 系列 Luckfox Pico 开发板构建固件（U-Boot、Linux kernel 5.10.160、Buildroot 2023.02.6 / Busybox rootfs、Rockchip 多媒体库、IPC 应用），一切由 `./build.sh`（软链到 `project/build.sh`）驱动。**没有需要长期运行的服务 / Web / dev server**——「应用」是运行在物理 ARM 硬件上的目标固件，无法在本 x86 VM 执行；验证「环境可用」的正确方式是**成功交叉编译并产出固件镜像**，而非启动进程。编译产物在 `output/image/`、`output/out/`、`IMAGE/`（均 gitignore）。

> 注：本仓与 ESP-IDF 项目（如 ESP-Pocket2 / WT9932P4-TINY）**不同**——那些是 ESP32 系列 MCU 的 `idf.py` 工程；本仓是 Rockchip RV1106 Linux SoC 的 buildroot 交叉编译 SDK，芯片级别、工具链与构建流程都不同（本仓用 `./build.sh` + 内置 `arm-rockchip830` 工具链，无 `idf.py`）。

### Cloud Agent 环境（Dockerfile 模式，配置即代码）

- 环境由 **`.cursor/environment.json` + `.cursor/Dockerfile`** 定义，不依赖个人快照。解析优先级：仓库 `.cursor/environment.json` > 个人 saved environment > 团队 saved environment；故从带本配置的分支起 Cloud Agent 会自动使用本 Dockerfile。
- **当前活动 = 自建 Ubuntu 24.04**（`.cursor/Dockerfile`：`FROM ubuntu:24.04` + SDK 全部编译依赖，tag+digest 双锁定）：贴合默认 agent / 本机的 24.04.4、开箱即编；超出官方仅支持的 22.04，但实测两板可编。
- **备选 = 官方镜像**（`.cursor/Dockerfile.luckfox_pico`：`FROM luckfoxtech/luckfox_pico:1.0`，Ubuntu 22.04，依赖预装、官方支持）：追求官方支持或规避 24.04 兼容风险时，把 `environment.json` 的 `dockerfile` 改指向它即可。
- ARM 交叉工具链 `arm-rockchip830-linux-uclibcgnueabihf`（gcc 8.3.0）**已随仓库内置**于 `tools/linux/toolchain/`，`build.sh` 选板后自动加入 `PATH`，**无需安装**。
- **Buildroot 下载包 `dl/` 不随仓库分发**：`sysdrv/source/buildroot` 已被 gitignore（`build.sh clean` 亦整目录删除），故**全新 / clean 后**构建 rootfs 需联网下载全部 buildroot 包（Pico Max 约 105 个 / Ultra W 约 153 个，含 mpv/madplay/sdl2 等多媒体包）；仅 in-tree 的 uboot / kernel 可离线（见下）。
- 桌面 / VNC / 字体等由 Cursor 平台启动时按 `/usr/local/share/vnc-desktop.Aptfile` 自动安装（本仓纯交叉编译、用不上，但平台仍会装）；**无需 docker-in-docker**——环境本身就是容器。

### 选板（非交互）

`./build.sh lunch` 为交互式三选（硬件版本 / 启动介质 / 系统），用 `printf` 经 stdin 喂入即可非交互选板：

| 开发板 | 菜单硬件项 | 启动介质 | 非交互命令 |
|---|---|---|---|
| **Luckfox Pico Max** | `[4] RV1106_Luckfox_Pico_Pro_Max`（Pro/Max 共用） | `[0] SD_CARD` | `printf '4\n0\n0\n' \| ./build.sh lunch` |
| **Luckfox Ultra W** | `[5] RV1106_Luckfox_Pico_Ultra`（含蓝牙） | `[0] EMMC`（无 SD 槽） | `printf '5\n0\n0\n' \| ./build.sh lunch` |

> 当前 dev 分支 SDK 无独立 `Pico_Max` / `Ultra_W` 配置：Pico **Max** 与 Pico **Pro** 共用 `Pro_Max` 配置（靠 SD_CARD / SPI_NAND 区分）；Ultra **W** 用 `Ultra` 配置（含 `rv1106-bt.config` 蓝牙）。选板会写出 `.BoardConfig.mk` 软链（gitignore）；其余 `build.sh` 子命令都要求先选板。
>
> ⚠️ 勿照 `README.md` 的 lunch 菜单示例选板：它是上游旧版、与当前 `dev` 的 `build.sh` 菜单不一致（README 把 Ultra W 列为 `[6]` 并引用不存在的 `RV1106_Luckfox_Pico_Ultra_W` 配置；当前实际 `[5]=Ultra`、`[6]=Pi`，且无任何 `*_Ultra_W-*` 板级文件）。一律以本文表格与 `build.sh` 当前菜单为准。

### 编译 / 验证

- **全量固件**：`./build.sh`（默认 `allsave`）→ 产出 `output/image/*.img`（`boot.img` / `uboot.img` / `rootfs.img` / `update.img` 等），并存档到 `IMAGE/<板>_RELEASE_TEST/`。其中 `sd_update.img` **仅 `SD_CARD` 介质生成**（Pico Max 有；Ultra W 走 EMMC，无此文件，以 `update.img` 为主）。
- **快速离线验证**：`./build.sh uboot`、`./build.sh kernel`（用 `sysdrv/source/` in-tree 源码，无需联网，几分钟）。
- **依赖自检**：`./build.sh check`（需先 `lunch`）。常用还有 `./build.sh clean <target>`、`./build.sh firmware`、`./build.sh info`。
- **⚠️ `./build.sh clean`（无参即 `clean all`）会删除 `.BoardConfig.mk`**：因此「clean 后再全量编译」需重新非交互 `lunch`，完整序列 `lunch → clean → lunch → ./build.sh`（定向清理如 `clean kernel` / `clean rootfs` 不删选板软链）。
- **成功判据**：`./build.sh` 退出码 0 **且** `IMAGE/` 下出现新存档目录。
- 三路径（本机 apt / 官方 docker / 自建 docker）× 两板的实测结果与耗时对比，见 `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` §7。

### 注意事项

- **不要在编译过程中滥用 `sudo`**：会改变文件属主导致编译失败（官方明确提示）。
- **编译会原地改写少量 git 跟踪的预编译件（提交前必须恢复）**：`./build.sh`(allsave) 会把 `project/app/wifi_app/hostapd-2.6/hostapd/hostapd`、`.../hostapd_cli` 与 `project/app/wifi_app/wifi/librkwifibt.so` 三者**由 `project/app/wifi_app/` 下源码交叉重编、覆盖仓库里跟踪的预编译副本**（`librkwifibt.so` 亦由 `wifi/` 下源码 `-shared` 链接生成，并非厂商 blob），编译后 `git status` 会显示这几个 modified。**提交前务必 `git status` 检查，并用 `git checkout -- <file>`（或 `git restore <file>`）恢复**，切勿误提交——否则会把环境相关的二进制噪音带进仓库、破坏可复现。切勿用 `.gitignore`（对已跟踪文件无效）；也不要删除这些跟踪副本（虽可由源码再生，但仓库需保留作基线）。其余 160+ 个预编译 `.so` 仅被读取 / 打包、不会被改写，无需处理。
- 不要从 Windows 复制 / 编辑源码树：它依赖 Linux 可执行位与软链（`build.sh` / `rkflash.sh` / `.BoardConfig.mk` 均为软链）。
- 这里没有 lint / 单元测试框架（嵌入式 C SDK），依赖校验用 `./build.sh check`。
