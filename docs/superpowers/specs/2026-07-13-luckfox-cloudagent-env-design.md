# Luckfox Pico Cloud Agent 环境 设计规格（Design Spec）

- **日期**：2026-07-13
- **状态**：已实现并实测通过（Implemented & Verified）
- **分支**：`cursor/setup-dev-environment-5fef`（起点 `dev`）
- **主题**：为 luckfox-pico SDK 引入 Cursor Cloud Agent 支持，将开发环境「配置即代码」化
- **关联代码文件**：`.cursor/environment.json`、`.cursor/Dockerfile`（当前活动=自建 Ubuntu 24.04）、`.cursor/Dockerfile.luckfox_pico`（官方镜像备选）、`AGENTS.md`
- **关联计划**：[`docs/superpowers/plans/2026-07-13-luckfox-cloudagent-env.md`](../plans/2026-07-13-luckfox-cloudagent-env.md)

---

## 1. 概述与目标

luckfox-pico 是 Rockchip RV1103/RV1106 的嵌入式 Linux 交叉编译 SDK，由仓库根目录的 `./build.sh`（软链到 `project/build.sh`）驱动，能够一键交叉编译并打包出可烧录的固件镜像（`output/image/*.img`）。

本设计的目标：**为 luckfox-pico 添加 Cursor Cloud Agent 支持，把开发环境做成「配置即代码」（Configuration as Code）**。任何人从本分支起一个 Cloud Agent，都应当获得一个**一致、可复现、开箱即可交叉编译出固件镜像**的环境，而不依赖任何个人手工搭建的 VM 快照。

具体而言，达成后的效果是：

1. Cloud Agent 启动即进入一个包含全部编译依赖的容器环境；
2. Agent 无需任何额外安装步骤，即可对 Luckfox Pico Max 与 Luckfox Ultra W 两款板子执行完整的 `allsave` 编译并产出固件镜像；
3. 环境定义完全落在版本库里（`.cursor/` 目录 + `AGENTS.md`），可审计、可回滚、可复现；
4. 为不同信任/网络场景提供三条编译路径（本机 apt / 官方 Docker 镜像 / 自建 Docker 镜像），并给出明确推荐。

## 2. 背景与参考

### 2.1 参考 PR（同类「配置即代码 / Dockerfile 模式」实践）

本设计沿用两个已合并的同类 PR 所确立的模式——用 `.cursor/environment.json` 的 **Dockerfile 模式** 固化环境，而非依赖手工 snapshot：

- **[ESP-Pocket2 #1](https://github.com/yuangezhizao/ESP-Pocket2/pull/1)**：以 Dockerfile 固化嵌入式工具链环境，实现 Cloud Agent 开箱即用。
- **[WT9932P4-TINY #2](https://github.com/yuangezhizao/WT9932P4-TINY/pull/2)**：同样采用配置即代码 / Dockerfile 模式为交叉编译项目提供一致环境。

两者的共同经验：**把「能编译」这件事的全部前置条件写进 Dockerfile，让 environment.json 只负责 `build`，从而使环境可复现、与个人机器无关。** 本设计的 spec/plan 结构亦对齐这两个 PR 的 `*-design.md` 文档骨架。

### 2.2 配置即代码（Configuration as Code）

Cursor Cloud Agent 支持两种环境定义方式：

- **快照（snapshot）**：手工在一台交互式 VM 里安装依赖，再「拍快照」。缺点是不可审计、难复现、易漂移。
- **Dockerfile 模式**：在 `.cursor/environment.json` 里声明 `build.dockerfile`，由 Cursor 在每次启动时从 Dockerfile 构建镜像。优点是环境定义进版本库、可 diff、可回滚、跨人一致。

本设计**明确选择 Dockerfile 模式**，把环境定义写死在仓库中。

### 2.3 为何默认不采用 dind（Docker-in-Docker）

编译本身**不需要** Docker：`./build.sh` 是纯粹的交叉编译脚本，工具链已内置。因此默认路径（官方镜像 / 自建镜像）都是「把编译依赖直接装进 Agent 运行的那个容器」，Agent 直接在容器里 `./build.sh` 即可，**无需在容器内再套一层 Docker**。

dind 只在一种情况下需要：当你想在 Agent 内**验证「官方 docker 镜像」这条路径本身**（即在 Agent 里 `docker run luckfoxtech/luckfox_pico:1.0` 再编译）时。此时才需要在 Cloud Agent 内跑 Docker，其代价见 §8 与 §9。因此 dind 被定位为「可选的验证手段」，而非默认架构。

## 3. 需求

### 3.1 功能需求

| 编号 | 需求 |
| --- | --- |
| F1 | Cloud Agent 启动后，无需交互即可对 `RV1106_Luckfox_Pico_Pro_Max`（Pico Max）与 `RV1106_Luckfox_Pico_Ultra`（Ultra W）执行完整编译并产出 `output/image/*.img`。 |
| F2 | 选板过程可非交互驱动（stdin 喂入），以便脚本化 / Agent 自动执行。 |
| F3 | 提供三条可选编译路径：本机 apt、官方 Docker 镜像、自建 Docker 镜像，且三者对两款板均实测可编译成功。 |
| F4 | 提供 `AGENTS.md`，向 Agent 说明仓库性质、验证方式（产出固件镜像而非拉起长期服务）、选板方式与路径推荐。 |

### 3.2 非功能需求

| 编号 | 需求 |
| --- | --- |
| N1 | **可复现**：同一分支、不同人、不同时间启动 Agent，得到的编译环境一致。 |
| N2 | **开箱即编**：不需要 Agent 额外执行安装命令（依赖在镜像构建期备好）。 |
| N3 | **保留官方支持环境、随时可切**：Luckfox 官方唯一声明支持的 Ubuntu 22.04 环境作为受支持备选保留（`.cursor/Dockerfile.luckfox_pico`）。注：本设计在「开箱一致」与「官方支持」间权衡后，活动基底选 24.04（见 §4.1），官方 22.04 为一键可切的备选。 |
| N4 | **不依赖个人快照**：环境定义全部进版本库，可审计、可回滚。 |
| N5 | **锁定可复现基线**：基础镜像用 tag + digest 双锁定，防止上游 tag 漂移导致不可复现。 |

## 4. 关键设计决策

### 4.1 为何选 Dockerfile 模式（活动基底：自建 Ubuntu 24.04；官方 22.04 镜像备选）

- **Dockerfile 模式**满足 N1/N2/N4：环境即代码。
- **活动基底 = 自建 Ubuntu 24.04**（`.cursor/Dockerfile`）：为开箱贴合默认 Cloud Agent 与本机（均 24.04.4），从裸系统自装 SDK 依赖。**官方镜像 `luckfoxtech/luckfox_pico:1.0`（Ubuntu 22.04，`.cursor/Dockerfile.luckfox_pico`）保留为受官方支持的备选**——它是 Luckfox 唯一声明支持的编译环境（依赖预装 gcc11/glibc2.35）。取舍见 §4.5/§5：24.04 超出官方支持但实测可编、贴合默认环境；需要官方支持时把 environment.json 的 `dockerfile` 改指向备选即可。（关于 N3「保留官方支持环境、随时可切」：本仓在「开箱一致」与「官方支持」之间选择了前者作为活动、后者作为随时可切的备选。）
- environment.json **只做 `build`、不做 `install`**：因为依赖已在镜像内；仓库属于 root 之外用户时的 git「dubious ownership」问题由 Dockerfile 内 `git config --system --add safe.directory '*'` 一次性解决（`--system` 写进镜像层，对所有用户生效），故不需要 `install` 阶段再补。

### 4.2 tag + digest 双锁定

基础镜像同时写 **tag + digest**：`FROM luckfoxtech/luckfox_pico:1.0@sha256:915d44588085826cbeda4b969dbbe7d5e54bf779ba36cda3c5072ee9533e0417`。

- **tag（`1.0`）**：可读、表意，指明这是官方 1.0。
- **digest（`sha256:915d4458…`）**：锁死到某个不可变镜像内容，杜绝「同一 tag 被上游重推」导致的不可复现（满足 N5）。

官方镜像在 Docker Hub 上**仅有 `1.0` 这一个 tag**（发布于 2023-11-11，约 287MB），没有更新版本，因此锁定它没有「错过新版本」的顾虑。

> 活动基底 `ubuntu:24.04` 同样 tag+digest 双锁定（`@sha256:4fbb8e6a…`）；与官方 `1.0` 不同，`24.04` 这个 tag 会随点版本滚动更新，故此处 digest 锁定尤为关键（当前锁定 digest 实测对应 24.04.4 LTS）。

### 4.3 工具链内置（无需安装交叉编译器）

ARM 交叉工具链 `arm-rockchip830-linux-uclibcgnueabihf`（gcc **8.3.0**）**已随仓库内置**于 `tools/linux/toolchain/`，在 `./build.sh lunch` 选板后会自动注入 PATH，**无需任何安装**。这意味着：无论宿主是 24.04 还是 22.04，真正参与目标固件编译的编译器是同一份，宿主的 host gcc 只用于编译构建期的 PC 侧工具。

### 4.4 buildroot 下载包 `dl/`（不随仓库，rootfs 构建需联网）

buildroot **2023.02.6** 由随仓库跟踪的源码包 `sysdrv/tools/board/buildroot/buildroot-2023.02.6.tar.gz` 提供，但其下载目录 `dl/` **不随仓库分发**：`sysdrv/source/buildroot` 已被 gitignore（`sysdrv/.gitignore` 第 9 行），且 `./build.sh clean` 会将该目录整体删除。因此**全新检出、或每次 `clean` 之后**构建 rootfs 都需联网下载全部 buildroot 包（Pico Max 约 105 个 / Ultra W 约 153 个）。

> 可离线的只有 in-tree 跟踪的 uboot / kernel（`./build.sh uboot` / `kernel`）；rootfs（buildroot）默认依赖外网，Ultra W 因多出多媒体包（mpv / madplay / sdl2 等）下载量更大——这也是 §8「docker 路径偏慢」的背景。
> 注：本环境磁盘上现存的 `dl/` 缓存是**先前构建产生**的，不代表仓库自带；换一台全新 Agent 不会有它。

### 4.5 活动用自建 Ubuntu 24.04、保留官方镜像备选

当前活动环境（`.cursor/Dockerfile`）采用**自建 Ubuntu 24.04**（`FROM ubuntu:24.04`），从裸系统自装全依赖。选 24.04 是为**开箱即用**：贴合默认 Cloud Agent 与本机（均 24.04.4）、少维护一个版本；虽超出官方仅支持 22.04 的范围，但已实测两款板均编译成功，且目标固件由内置交叉工具链决定、与官方 22.04 镜像功能预期一致（见 §5/§7）。同时保留 `.cursor/Dockerfile.luckfox_pico`（官方 22.04 镜像）作为**受官方支持的备选**：它相对老旧、缺 `curl`、但依赖预装开箱即编，适合追求「官方支持」或规避 24.04 兼容风险时切换（改 environment.json 的 `dockerfile` 指向即可）。踩到的 buildroot 依赖坑（见 §8）已在自建 Dockerfile 固化为可复现清单。

## 5. 三路径方案对比与推荐

三条路径**对两款板均实测编译成功**（成功判据 = 退出码 0 + 新存档 + `output/image/*.img`；其中 Pico Max 用 SD_CARD 介质，另对 Pico Max 的 **SPI_NAND** 介质补测通过，见 §7.3.1）。产物**功能预期一致**——因同一份源码 + 同一份内置交叉工具链，可推断目标固件功能相同；但**本次仅验证到「均成功产出完整固件 + 组件版本一致」，未做板上启动 / 外设功能回归**（另注：buildroot / U-Boot 内嵌构建时间戳，镜像**非字节一致**，见 §7.3）。

| 维度 | 路径 1：本机 apt | 路径 2：官方 Docker 镜像 | 路径 3：自建 Docker 镜像 |
| --- | --- | --- | --- |
| 基础环境 | 当前 VM Ubuntu **24.04**（gcc13 / glibc2.39 / cmake3.28 / py3.12） | `luckfoxtech/luckfox_pico:1.0` = Ubuntu **22.04**（gcc11 / glibc2.35 / cmake3.22 / py3.10） | `ubuntu:24.04`（gcc13 / glibc2.39，自装依赖，贴合默认 agent / 本机） |
| 依赖来源 | 按官方《SDK 镜像编译》apt 清单手工安装 | 镜像已预装编译依赖 | 官方 apt 清单 + 补齐 buildroot 硬依赖（见 §8） |
| 官方支持 | 否（24.04 非官方声明支持） | **是（官方唯一声明支持环境）** | 否（24.04 超官方支持，实测可编），依赖自列 |
| 可复现性 | 依赖当前 VM apt 源状态 | tag+digest 双锁定，高 | tag+digest 双锁定，高；依赖清单自控 |
| 需要 dind | 否 | 否（把依赖直接装进 Agent 容器）；仅「在 Agent 内验证该镜像」时才需 | 否 |
| 缺陷 / 注意 | 非官方环境，理论上环境相关风险略高 | 镜像缺 `curl`（已在 `.cursor/Dockerfile.luckfox_pico` 补装） | 官方 apt 清单遗漏 `wget`/`patch`；`which` 勿写入清单（见 §8） |
| 目标产物 | 交叉工具链 gcc8.3.0 / kernel5.10.160 / buildroot2023.02.6 **版本一致、功能预期一致**（未板上验证；非字节一致） | 同左 | 同左 |

### 推荐

- **当前活动：路径 3（自建 Ubuntu 24.04）** —— environment.json 引用的 `.cursor/Dockerfile` 即此方案，开箱贴合默认 agent/本机（24.04.4）、实测两板可编。取舍：超出官方仅支持的 22.04，换取「与默认环境一致、少维护一个版本」。
- **受官方支持的备选：路径 2（官方 Docker 镜像）** —— `.cursor/Dockerfile.luckfox_pico`，官方唯一声明支持、依赖预装；追求官方支持或规避 24.04 兼容风险时，把 environment.json 的 `dockerfile` 改指向它即可。
- **路径 1（本机 apt）** —— 主要用于对照验证与快速本地实验。

## 6. 板型映射

> 当前 `dev` 版本**没有**独立的 `_Max` / `_W` 板级配置；市售型号需映射到 SDK 现有配置。

| 市售型号 | SDK 板名（lunch 选项） | 启动介质 / 系统 | 非交互选板命令 | 关键特征 |
| --- | --- | --- | --- | --- |
| Luckfox **Pico Max** | `RV1106_Luckfox_Pico_Pro_Max` | SD_CARD / Buildroot | `printf '4\n0\n0\n' \| ./build.sh lunch` | 有 SD 卡槽 |
| Luckfox **Ultra W** | `RV1106_Luckfox_Pico_Ultra` | EMMC / Buildroot | `printf '5\n0\n0\n' \| ./build.sh lunch` | 板载 eMMC、无 SD 卡槽；配置含 `rv1106-bt.config`（蓝牙） |

选板菜单三级选择依次为「硬件型号 → 启动介质 → 系统类型」，`printf '<hw>\n0\n0\n'` 分别对应三次回车输入；`build.sh lunch` 的硬件菜单里 `RV1106_Luckfox_Pico_Pro_Max` 为第 4 项（索引 4）、`RV1106_Luckfox_Pico_Ultra` 为第 5 项（索引 5），后两个 `0` 取各自默认的启动介质与系统。

### 6.1 启动介质变体

`./build.sh lunch` 的启动介质候选为 `SD_CARD` / `SPI_NAND` / `EMMC`，具体可选项由硬件与 SDK 板级配置共同决定：

| 启动介质 | 含义 | rootfs 文件系统 |
| --- | --- | --- |
| `SD_CARD` | 外插 SD 卡启动 | ext4（Buildroot） |
| `SPI_NAND` | 板载 SPI NAND 启动 | UBIFS |
| `EMMC` | 板载 eMMC 启动 | ext4（Buildroot） |

两款目标板可用的介质并不相同：

- **Pico Max（`RV1106_Luckfox_Pico_Pro_Max`）**：有 SD 卡槽，提供 `SD_CARD` 与 `SPI_NAND` 两种介质（对应 `BoardConfig-SD_CARD-Buildroot-…` 与 `BoardConfig-SPI_NAND-Buildroot-…`）；默认取 `SD_CARD`。两种介质均已实编实测通过（SD_CARD 见 §7.3，SPI_NAND 见 §7.3.1 / §11.1 Q12）。
- **Ultra W（`RV1106_Luckfox_Pico_Ultra`）**：板载 eMMC、**无 SD 卡槽**，SDK 仅提供 `EMMC` 介质（`BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk`），故启动介质只能是 EMMC。

因此非交互选板命令里第二个 `0`（介质）对 Pico Max 取到 `SD_CARD`、对 Ultra W 取到 `EMMC`，均为各自默认项。

## 7. 验证策略

### 7.1 非交互选板

`./build.sh lunch` 为交互式三选，Agent/脚本用 `printf` 经 stdin 喂入即可非交互选板（见 §6 命令）。选板成功后 `.BoardConfig.mk` 会软链到对应板级配置文件（例：`project/cfg/BoardConfig_IPC/BoardConfig-SD_CARD-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk`）。

### 7.2 编译与成功判据

- 编译命令：默认 `./build.sh` 即 **allsave**（全量编译 + 固件打包）。
- **成功判据（两条同时满足）**：
  1. `IMAGE/<板>_RELEASE_TEST/` 下出现**新的存档目录**；
  2. `./build.sh` **退出码为 0**。
- **产物**：`output/image/*.img`（`update.img`、`rootfs.img`、`boot.img`、`uboot.img`、`oem.img`、`env.img`、`userdata.img`、`idblock.img`、`download.bin` 等）。
- 存档目录命名形如：
  - Pico Max：`IMAGE/IPC_SD_CARD_BUILDROOT_RV1106_LUCKFOX_PICO_PRO_MAX_<YYYYMMDD.HHMM>_RELEASE_TEST/`
  - Ultra W：`IMAGE/IPC_EMMC_BUILDROOT_RV1106_LUCKFOX_PICO_ULTRA_<YYYYMMDD.HHMM>_RELEASE_TEST/`
- `./build.sh clean`（无参即 `clean all`）约 18s，可在切板/复测之间清理；注意它会删除 `.BoardConfig.mk`，故 clean 后须重新非交互 `lunch` 再编译（完整序列 `lunch → clean → lunch → allsave`；定向清理如 `clean kernel`/`rootfs` 不删选板软链）。

### 7.3 实测结果表（含耗时）

三路径 × 两板全部实测**成功**（退出码 0 + 新存档目录）。**clean 全量口径**耗时（2026-07-13：每组按 `lunch → clean → lunch → allsave` 执行——`./build.sh clean` 即 `clean all`、会删除 `.BoardConfig.mk`，故 clean 后须重新 `lunch`——计 `build.sh` 全过程；**因 clean 会删除 buildroot、每次都重新联网下载全部包（Max 约 105 / Ultra 约 153 个），故耗时含下载、受网络波动影响，非纯编译对比**）：

| 板型 | 路径 1：本机 native（24.04） | 路径 2：官方 docker（22.04） | 路径 3：自建 docker（24.04） |
| --- | --- | --- | --- |
| Pico Max（`RV1106_Luckfox_Pico_Pro_Max`） | **35m11s**（2111s） | **27m51s**（1671s） | **26m48s**（1608s） |
| Ultra W（`RV1106_Luckfox_Pico_Ultra`） | **41m2s**（2462s） | **49m2s**（2942s） | **44m38s**（2678s） |

#### 7.3.1 SPI_NAND 补测（2026-07-16，Pico Max，三路径铺满）

上表 6 组的 Pico Max 用的是 **SD_CARD** 介质；另对 Pico Max 的 **SPI_NAND** 介质**在三条路径上各实编一次**（每次 `printf '4\n1\n0\n' | ./build.sh lunch` → clean → 重选板 → `allsave`；docker 两路径以 `--privileged -v /workspace:/home` 挂载、编后 `chown` 复原属主并 `git checkout` 复原被改写的跟踪件）。**耗时口径统一为「`allsave` 全过程」**（不含前置 clean/lunch 的约 20s；含 buildroot 联网下载），故与上表 6 组的「clean 全量」口径略有差异、仅宜横向比 SPI_NAND 三路径：

| 路径 | 结果 / `allsave` 耗时 | 存档 `IMAGE/IPC_SPI_NAND_..._PRO_MAX_<时间>_RELEASE_TEST` | `rootfs.img`(UBI) | `update.img` | `oem.img` |
| --- | --- | --- | --- | --- | --- |
| 1 本机 native（24.04） | ✅ rc=0，**26m6s**（1566s） | `…20260716.0924…` | 55,050,240 B | 82,051,658 B | 20,054,016 B |
| 2 官方 docker（22.04） | ✅ rc=0，**28m12s**（1692s） | `…20260716.2233…` | 55,050,240 B | 82,051,658 B | 20,054,016 B |
| 3 自建 docker（24.04） | ✅ rc=0，**27m1s**（1621s） | `…20260716.2305…` | 55,050,240 B | 82,051,658 B | 20,054,016 B |

- **三路径均编译成功（rc=0 + 各自新存档）**，且三者 `rootfs.img` / `update.img` / `oem.img` **字节大小完全一致**（`rootfs.img` 经 `file` 确认为 `UBI image`）——进一步印证「目标产物由内置交叉工具链决定、与宿主环境无关」。
- **容量**：`rootfs.img`(UBI) **≈52.5 MiB（55,050,240 B）**，占 **210MB** rootfs 分区约 25%、**余量约 75%**，放得下且宽裕；IPC 应用经 `RK_BUILD_APP_TO_OEM_PARTITION=y` 分流到 `oem.img` **≈19.1 MiB**（30MB 分区内）。`update.img` 整包 **≈78 MiB（82,051,658 B）**（**非**早期臆测的「约 14MB」）。其余：`boot.img` 3.6M、`uboot.img` 256K、`env.img` 256K、`idblock.img` 184K、`userdata.img` 1.9M。
- 说明：实体板实烧 / 上电启动本环境无硬件、未做（容量与烧录细节见 §11.1 Q12）。

> 观察：Pico Max 上 docker 两法（26–28min）反比 native（35min）快；Ultra W 上 native（41min）最快、官方 docker（49min）最慢、自建 docker（44min）居中。数据均为实测（`IMAGE/*_RELEASE_TEST` 时间戳与完成时刻对应），但**含下载时间**、且下方所述 native 与 docker 非同一批次，故仅宜粗略参考、不宜精确比大小。
> 批次说明：上表 docker 4 项来自同一批次连续运行；native 2 项因当时与 docker 交替共用工作区导致属主权限冲突（root/ubuntu）而在该批次内失败，系稍后**单独重跑补测**，故与 docker 非严格同批次。早期混合口径数据（native/官方 docker 的 Ultra W 曾为**增量**：18m42s / 22m27s；自建 clean 全编 26.5min / 43.8min）因口径不一，已由上表取代。

- **目标侧一致性**：无论宿主 24.04 还是 22.04，参与目标固件编译的交叉工具链（gcc **8.3.0**）/ kernel **5.10.160** / buildroot **2023.02.6** 都是同一份内置源码，故可推断产物功能一致、host gcc 不进入目标编译（此为基于相同构建输入的**推断**；已验证的是「编译成功 + 组件版本一致」，**未含板上启动 / 外设功能回归**）。
- 因耗时**含下载**且 native 与 docker **非同批次**，各方式的速度差主要受镜像下载站点与网络波动影响（见 §8），不足以据此精确断言「宿主环境 / 工具链版本对编译速度的影响」。
- Ultra W 上官方 docker 偏慢的主因见 §8（缺 curl → 镜像测速失效 → 下载回落上游站点），属**下载行为差异**、非 docker 架构或工具链问题。
- ⚠️ **口径归属**：上表「官方 docker(22.04)」列反映的是**原始官方镜像 `luckfoxtech/luckfox_pico:1.0`（本就缺 curl）**的行为；本仓交付的备选 `.cursor/Dockerfile.luckfox_pico` **已补装 `curl`**，实际用该备选时不再有此镜像测速惩罚、Ultra W 偏慢应随之缓解，故此列耗时**不代表**交付备选镜像的表现。

## 8. 关键发现（Key Findings）

1. **自建镜像：官方 apt 清单遗漏 buildroot 硬依赖 `wget` 与 `patch`。**
   - 缺 `wget` → buildroot 报 `You must install 'wget'`。
   - 缺 `patch` → buildroot 报 `You must install GNU patch`。
   - 修复：自建镜像需在官方清单外补 `wget patch`（及一批常用工具，见下）。

2. **`which` 不该写进 apt 清单（重要坑）。**
   - `which` **无独立实体包**——命令由 essential 包 `debianutils` 内置，基础镜像已自带。
   - 在 **Ubuntu 24.04**（universe 默认开启）上 `apt-get install which` 会解析到虚包 **`gnu-which`** 并**安装成功（退出 0）**——只是徒增冗余包、并可能改写 `which` 命令的 alternatives；而在**官方镜像 Ubuntu 22.04**（原始实测环境）上会报 `E: Unable to locate package which`，导致镜像构建/编译**退出码 100** 而失败。
   - 结论：**自建镜像依赖清单中绝不写 `which`**（24.04 徒增冗余包、22.04 直接失败，且命令本就内置）。
   - 自建正确依赖 = 官方 apt 清单 + 补 `wget patch bzip2 xz-utils perl gzip tar findutils sed`（**不含 which**）。

3. **官方镜像缺 `curl`。**
   - `luckfoxtech/luckfox_pico:1.0` 内没有 `curl`。已在 `.cursor/Dockerfile.luckfox_pico`（官方镜像备选方案）中补装（连同 `sudo vim less file htop`）。

4. **docker 路径偏慢的主因是「缺 curl 致镜像测速失效、下载回落上游站点」，而非 docker 本身。**
   - Ultra W 独有的多媒体包（mpv / madplay / sdl2 等）需联网下载（`dl/` 本就不随仓库，见 §4.4）。
   - buildroot 的下载**全程用 `wget`**（`support/download/` 无 curl 后端）；`curl` 只被 `sysdrv/tools/board/mirror_select/buildroot_mirror_select.sh` 用于构建初**测速选最快镜像**。官方镜像缺 `curl` → 测速失败 → 日志 `Fast mirror is`（空）→ `BR2_PRIMARY_SITE=""` → 各包回落到上游默认站点（实测如 `ftpmirror.gnu.org`）而非预设镜像 `sources.buildroot.net`，故偏慢。
   - 因此这是**缺工具导致的下载站点差异**（并非「每包 curl→wget 重试」，也与 docker 架构 / 工具链无关）；补 `curl` 恢复镜像测速即改善。

5. **Cloud Agent 的模型不能在 `.cursor/environment.json` 指定。**
   - `environment.json` 的 schema 只有 `snapshot` / `build` / `install` / `start` / `terminals` 字段，**没有 `model` 字段**。
   - 模型只能经以下途径指定：UI 模型下拉（单次会话）、Dashboard 默认模型、Automations、或 API 的 `model.id`；且必须是**支持 Max Mode 的精选模型**。
   - 该发现影响的是「如何为该环境选模型」的运维说明，不影响环境定义本身。

## 9. 风险与权衡

| 风险 / 权衡 | 说明 | 缓解 |
| --- | --- | --- |
| 官方镜像老旧（2023-11-11）且缺工具 | 唯一 tag `1.0`，无更新；缺 curl 等 | tag+digest 锁定保证可复现；在 `.cursor/Dockerfile.luckfox_pico`（官方镜像备选）补装 curl 等 |
| Ultra W 多媒体包需联网；`dl/` 不随仓库 | `dl/` 不随仓库（见 §4.4），rootfs 包首次 / clean 后需联网下载 | 用 wget 下载即可成功；缺 curl 仅致镜像测速失效、下载回落上游站点而偏慢（见 §8 第 4 条），补 curl 改善 |
| 24.04（活动 / 路径1 / 3）非官方支持 | 理论上环境相关风险略高 | 已实测两板可编、产物与官方功能预期一致（未板上验证）；如需官方支持可一键切备选官方 22.04 镜像（`.cursor/Dockerfile.luckfox_pico`） |
| 自建镜像依赖清单易漏 | 官方清单漏 wget/patch，且 which 是陷阱 | 在 spec/plan/`.cursor/Dockerfile`（自建 ubuntu24）中固化正确清单与注释 |
| 在 Agent 内跑 docker 成本 | dind 需 `apt install docker.io` + `fuse-overlayfs` 存储驱动 + `iptables-legacy` + 手动 `dockerd`（Cloud Agent 无 systemd） | 默认不 dind；仅在需验证「官方镜像路径」时启用 |
| 上游删除/变更基础镜像 | 供应链风险 | digest 锁定；必要时可切自建镜像路径 |

## 10. 交付物清单（Deliverables）

| 文件 | 作用 | 关键点 |
| --- | --- | --- |
| `.cursor/environment.json` | Cloud Agent 环境定义 | Dockerfile 模式：`{"build":{"dockerfile":"Dockerfile","context":".."}}`；纯 `build`、无 `install`（safe.directory 由 Dockerfile 的 `--system` 处理） |
| `.cursor/Dockerfile` | **当前活动**环境（自建 Ubuntu 24.04，environment.json 引用本文件） | `FROM ubuntu:24.04@sha256:4fbb8e6a…` + 官方 apt 清单 + `wget patch bzip2 xz-utils perl gzip tar findutils sed` + `curl` + `sudo`/`ca-certificates`/`locales` + git safe.directory（**不含 which**）；附「平台自动安装包」注释框 |
| `.cursor/Dockerfile.luckfox_pico` | 备选环境（官方镜像 Ubuntu 22.04，官方支持） | `FROM luckfoxtech/luckfox_pico:1.0@sha256:915d4458…`（tag+digest 双锁定）+ 补 `sudo curl vim less file htop` + `git config --system --add safe.directory '*'`；附「平台自动安装包」注释框 |
| `AGENTS.md` | 给 Agent 的仓库说明（精简） | 中文交互约定、仓库性质（验证=产出固件镜像、无长期服务、luckfox≠ESP-IDF）、活动 / 备选环境、工具链内置、非交互选板、构建 / 验证命令、编译污染提醒；编译实测数据见本 spec §7 |

> 关键 digest 记录：官方镜像 `sha256:915d44588085826cbeda4b969dbbe7d5e54bf779ba36cda3c5072ee9533e0417`；自建基底 `ubuntu:24.04` `sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`。

## 11. QA（设计澄清 Q&A）

**Q1：为什么不用 snapshot，而用 Dockerfile？**
A：snapshot 不可审计、易漂移、难复现。Dockerfile 模式把环境写进版本库，满足可复现（N1）、可审计（N4）。

**Q2：为什么活动基底选 Ubuntu 24.04，而不是官方那个老镜像？**
A：为**开箱即用**——默认 Cloud Agent 与本机均为 24.04.4，活动基底用同版本可最大化贴合、少维护一版，且已实测两板可编、产物与官方功能预期一致（未板上验证）。官方 22.04 镜像（唯一声明支持、依赖预装、开箱即编）保留为**受官方支持的备选**（`.cursor/Dockerfile.luckfox_pico`）：它虽老（缺 curl）但可控——digest 锁定 + Dockerfile 补工具即可；追求官方支持或规避 24.04 兼容风险时一键切它。详见 §4.1 / §4.5 / Q9 / Q11。

**Q3：environment.json 里能不能顺便指定用哪个模型？**
A：**不能。** environment.json 的 schema 只有 snapshot/build/install/start/terminals，没有 model 字段。模型只能通过 UI 下拉 / Dashboard 默认 / Automations / API `model.id` 指定，且须为支持 Max Mode 的精选模型。

**Q4：为什么 environment.json 只有 build，没有 install？**
A：依赖已经在镜像构建期备齐；唯一需要在运行期处理的 git「dubious ownership」也已由 Dockerfile 里的 `git config --system --add safe.directory '*'` 解决（`--system` 落在镜像层，对所有用户生效）。因此不需要 install 阶段。

**Q5：编译要不要 docker-in-docker？**
A：默认**不要**。编译只靠内置交叉工具链，直接在 Agent 容器里 `./build.sh` 即可。只有当你想在 Agent 内部再验证「官方 docker 镜像」这条路径时，才需要 dind（需 fuse-overlayfs + iptables-legacy + 手动 dockerd）。

**Q6：三条路径产物会不会不一样？**
A：**功能预期一致，但非字节一致，且未做板上验证**。目标固件由内置交叉工具链（gcc8.3.0）/ kernel5.10.160 / buildroot2023.02.6 同一份源码编出，宿主 host gcc 只参与构建期 PC 工具、不进入目标产物，故可**推断**功能相同——但本次仅验证到「6 组均成功编译产出 + 组件版本一致」，**未在实体板上启动 / 跑外设回归**，「功能一致」是基于相同构建输入的推断而非实测。另外 buildroot / U-Boot 会嵌入构建时间戳等，故同板不同次 / 不同环境的 `update.img` 等 sha256 不同（要字节可复现需另行固定 `SOURCE_DATE_EPOCH` 等，本 SDK 未做）。

**Q7：为什么自建镜像清单要额外补 wget/patch，却不能写 which？**
A：官方《SDK 镜像编译》apt 清单遗漏了 buildroot 的硬依赖 `wget`（否则报 `You must install 'wget'`）和 `patch`（否则报 `You must install GNU patch`）。而 `which` 无独立实体包（命令由 debianutils 内置）：在活动基底 Ubuntu 24.04（universe 默认开启）上写它会解析到虚包 `gnu-which` 并安装成功（退出 0）、徒增冗余包，在官方镜像 22.04 上则报 `E: Unable to locate package which` 致退出码 100。故正确做法是补 `wget patch …` 但绝不写 `which`。

**Q8：docker 路径为什么在 Ultra W 上更慢？会不会是 docker 本身慢？**
A：不是 docker 慢。主因是官方镜像缺 `curl`：buildroot 下载全用 wget，但 curl 用于构建初的镜像测速；缺 curl → 测速失败 → 主镜像站点为空 → 各包回落到上游默认站点（如 ftpmirror.gnu.org）下载，比预设镜像慢，补 curl 恢复测速即改善（详见 §8 第 4 条）。注意：该耗时对比**含下载**、且 native 与 docker **非同批次**，故为粗略参考。

**Q9：为什么活动用自建 24.04，还保留官方镜像备选？**
A：活动用自建 Ubuntu 24.04（`.cursor/Dockerfile`）是为**开箱即用**——贴合默认 Cloud Agent 与本机（24.04.4）、少维护一版；已实测两板可编、产物与官方功能预期一致（未板上验证、内置交叉工具链决定）。保留官方 22.04 镜像备选（`.cursor/Dockerfile.luckfox_pico`）则因为：(1) 它是官方唯一声明支持环境；(2) 依赖预装、开箱即编；适合追求官方支持或规避 24.04 兼容风险时切换（改 environment.json 的 `dockerfile` 指向）。自建方案踩到的坑（`wget`/`patch` 必补、`which` 是陷阱）已固化为可复现清单。

**Q10：Ultra W 为什么用 EMMC 而不是 SD 卡？**
A：Ultra W 硬件**板载 eMMC 且无 SD 卡槽**，启动介质只能是 EMMC；本仓库 `dev` 版 SDK 中 Ultra 也仅提供 EMMC 板级配置（`BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Ultra-IPC.mk`），没有 SD_CARD / SPI_NAND 变体。相较之下 Pico Max 有 SD 卡槽，提供 `SD_CARD` 与 `SPI_NAND` 两种介质。因此非交互选板时 Ultra W 的介质项默认取到 EMMC（见 §6.1）。

**Q11：自建镜像为什么从 Ubuntu 22.04 改为 24.04？**
A：为「开箱即用」——默认 Cloud Agent 与本机均为 Ubuntu 24.04.4，自建镜像选同版本可最大化贴合、减少版本维护面。代价是超出官方仅支持 22.04 的范围（gcc13 / glibc2.39 vs 22.04 的 gcc11 / glibc2.35），但已于 2026-07-13 用 `FROM ubuntu:24.04` 自建镜像对两款板实跑 clean 全量编译，均 `EXIT=0` 且产出完整固件（Pico Max 打包 490M、Ultra W 926M / rootfs 404M）。目标固件由内置交叉工具链（gcc8.3.0）编出，与官方 22.04 镜像功能预期一致（未板上验证），故切 24.04 不影响目标产物。注意：**2026-07-14 起活动 `.cursor/Dockerfile` 即自建 Ubuntu 24.04**（原官方镜像已重命名为 `.cursor/Dockerfile.luckfox_pico` 作备选）；environment.json 引用不变，故将来新建 agent 即以 24.04 开箱。

**Q12：Pico Max 能否烧到板载 SPI NAND、免插 SD 卡？当前 buildroot 产物放得下吗？**
A：**能——已于 2026-07-16 在三条路径（native / 官方 docker / 自建 docker）上各实编实测通过（均 clean 全量、退出码 0，`allsave` 26m6s / 28m12s / 27m1s）**，产出完整 SPI_NAND 固件、rootfs 放得下且余量极大，且三路径产物字节大小一致（明细见 §7.3.1）。Pico Max 板载 256MB SLC SPI NAND（Winbond W25N02KV），SD 卡对它是可选、NAND 才是主存储；SDK 有现成配置 `BoardConfig-SPI_NAND-Buildroot-RV1106_Luckfox_Pico_Pro_Max-IPC.mk`，与 SD_CARD 共用同一 DTS / 物理板、二选一启动。存档（各路径一份）：`IMAGE/IPC_SPI_NAND_BUILDROOT_..._PRO_MAX_20260716.{0924,2233,2305}_RELEASE_TEST`。
- **选板（非交互）**：`printf '4\n1\n0\n' | ./build.sh lunch`（硬件 4=Pro_Max、介质 **1=SPI_NAND**、系统 0=Buildroot；对比 SD 卡为 `printf '4\n0\n0\n'`），再 `./build.sh`。
- **容量能否放下（已实测：放得下、余量约 75%）**：SPI_NAND 分区表 rootfs 分区 **210MB**（另含 `env`/`idblock`/`uboot`/`boot 4M`/`oem 30M`/`userdata 10M`；分区 / 文件系统细节另见 §11.1 QA-3），文件系统为 **UBIFS/UBI**（压缩 lzo/zlib + 坏块管理 / 磨损均衡，非 ext4）。实测产物（`file` 确认 `rootfs.img` = `UBI image`）：**`rootfs.img` ≈ 52.5 MiB（55,050,240 B）**，远小于 210MB 分区（约用 25%、留 ~157MB），**放得下且余量极大**；IPC 应用因 SPI_NAND 配置启用 `RK_BUILD_APP_TO_OEM_PARTITION=y` 装入独立 `oem` 分区，**`oem.img` ≈ 19.1 MiB（20,054,016 B）**（在 30MB 分区内）。对照 **SD_CARD** 下 rootfs 内容约 **196MB**（ext4 `rootfs.img` 198.8MB，应用在 rootfs 内）——SPI_NAND 因「应用分流到 oem + UBIFS 压缩」故 rootfs 本体大幅缩小。
- **烧录（产物已实编，实体板烧录/启动未做）**：SPI_NAND 全量产物 **`update.img` ≈ 78 MiB（82,051,658 B）**（含各分区；⚠️ 非早期臆测的「约 14MB」），经 USB Type-C 进 MaskROM / Loader，用 SocToolKit（Windows）/ `upgrade_tool`（Linux）烧进 NAND，烧完脱卡即从 NAND 启动、**无需 SD 卡**。注：镜像已实编产出，但实体板实烧 / 上电启动本环境无法进行（无硬件），属流程说明。
- **系统类型**：本 SDK（IPC）选板时系统菜单**只展示 `Buildroot`（默认、全功能）**——`Custom` 虽是 `build.sh` 里 `LF_SYSTEM` 的内部枚举（对 SD_CARD/EMMC 输入 `1` 会拼到它），但仓库无任何 `BoardConfig-*-Custom-*` 板级文件，选它会失败；`project/cfg/BoardConfig_IPC/` 实含 13 个 Buildroot + 2 个 **Busybox FASTBOOT 变体（EMMC/Ultra 与 SPI_NAND/Pro_Max 各一，rootfs 极小、启动快）** 配置；**无 Ubuntu**（Luckfox 另有 Ubuntu 方案，但不在本 IPC 分支）。默认 buildroot 逼近分区上限时，可改用 Busybox FASTBOOT 变体大幅瘦身。

**Q13：rootfs 用 Buildroot 还是 Busybox？怎么选、各自优缺点？**
A：先厘清概念——**Busybox 是「把几百个精简 UNIX 命令 + 基础 init 合成的单个二进制」，Buildroot 是「自动生成完整 rootfs 的构建系统」；Busybox 只是 Buildroot 产出的 rootfs 里的一个组件（Buildroot 默认用它当 shell/init）**，二者并非平级二选一。本 SDK 借 `LF_TARGET_ROOTFS` 提供两种 rootfs 方案：
- **怎么选**：`./build.sh lunch` 的系统菜单**只展示 `Buildroot`（默认）**（`Custom` 为 `LF_SYSTEM` 内部枚举，但无对应 IPC 板级文件、选它会失败）；**Busybox 方案也不在菜单**，它是独立配置 `BoardConfig-*-Busybox-*-IPC_FASTBOOT.mk`（`LF_TARGET_ROOTFS=busybox` + `RK_ENABLE_FASTBOOT=y`），需**手动软链**后再编：`ln -sf project/cfg/BoardConfig_IPC/BoardConfig-SPI_NAND-Busybox-RV1106_Luckfox_Pico_Pro_Max-IPC_FASTBOOT.mk .BoardConfig.mk && ./build.sh`。
- **优缺点对比**：

| 维度 | `buildroot`（完整，默认） | `busybox`（极简 + FastBoot） |
| --- | --- | --- |
| rootfs 内容 | 完整：多媒体 mpp/rockit/rkaiq ISP + 通用 IPC 应用、可读写 | 极简：去多媒体/WiFi/test，打进 boot（erofs 只读），**无独立 rootfs 分区** |
| 体积 / 启动 | ≈196MB（SD_CARD/Pico Max·ext4；Ultra W/EMMC 更大）/ 常规启动 | 极小 / **秒·亚秒级快启**（fastboot） |
| 应用 | 通用 `RKIPC_RV1106` | 特定 `RK_FASTBOOT_SERVER` / `SMART_DOOR` demo |
| 可扩展性 | 强（可读写 ext4、可手动部署 / 调试；但**无 opkg/apt 等运行时包管理器**，增删正式软件需改 defconfig 重编） | 弱（只读、功能固定、二次开发需移植） |
| 如何选择 | `lunch` 默认可选 | 不在菜单，手动软链 BoardConfig |
| 官方/社区支持 | 完善（Buildroot 生态、SDK 默认） | 小众、专用、资料少 |

- **推荐**：绝大多数场景用 **`buildroot`**（默认、功能全、可扩展、官方主推）；仅当做「上电秒开摄像头、功能固定、存储/内存极紧」的量产设备（如智能门铃 / 猫眼）才用 `busybox` FastBoot 变体（且它绑定特定 demo、只读难改、需手动配置）。

### 11.1 使用 / 验证答疑（QA 汇总，2026-07-12 实测；原为 PR 评论、现并入本 spec）

> 下列 Q&A 于 2026-07-12 首次以 PR 评论形式给出，现迁移归档于此。其中耗时为当日**早期混合口径**，统一全量口径实测见 §7.3。

**QA-1：`luckfoxtech/luckfox_pico` 有哪些 Docker tag？有无新版？**
Docker Hub 上仅 `1.0` 一个 tag（287MB，2023-11-11 发布后未更新），即官方唯一且最新版本；备选的 `.cursor/Dockerfile.luckfox_pico` 用 `1.0@sha256:915d4458…`（tag+digest 双锁定）。

**QA-2：本机 vs Docker 编译耗时对比？慢在哪？**
（早期混合口径；最新全量口径见 §7.3）Pico Max 本机 26m55s / docker 26m48s（几乎同速）；Ultra W 本机 18m42s（增量）/ docker 22m27s。差异**既非工具链版本、也非 docker / 挂载开销**——Pico Max 几乎同速即铁证（目标侧交叉工具链 gcc8.3.0 / kernel / buildroot 完全相同）。Ultra W 那约 20% 的根因是**官方镜像缺 `curl`**：Ultra 独有多媒体包（mpv / madplay / sdl2 / harfbuzz…）`dl/` 未预置需联网，buildroot 先试 curl（失败）再回退 wget，每包多一次重试累积约 4 分钟——属镜像配置问题、非架构问题，官方镜像方案已补 `curl` 消除。（**机制更正**：buildroot 下载实际全用 wget，`curl` 仅用于镜像测速；缺 curl 导致测速失败、下载回落上游站点，**并非**「每包 curl→wget 重试」，详见 §8 第 4 条。此处保留当日评论原文，以更正说明为准。）

**QA-3：`SPI_NAND` 变体是什么？**
本质是 `RK_BOOT_MEDIUM`（启动 / 存储介质）不同，对应不同分区表与打包：

| | SD_CARD（Pico Max） | SPI_NAND（Pico Max 可选） | EMMC（Ultra W） |
|---|---|---|---|
| `RK_BOOT_MEDIUM` | `sd_card` | `spi_nand` | `emmc` |
| 介质 | 可插拔 SD / TF 卡 | 板载 SPI NAND 闪存 | 板载 eMMC |
| DTS | `…pico-pro-max.dts` | `…pico-pro-max.dts`（同一块板） | `…pico-ultra.dts` |
| rootfs 分区 | 占满整卡 | 210M 固定（NAND ~256M） | 6G |
| rootfs 文件系统 | ext4 | UBI / UBIFS（NAND 专用） | ext4 |

即 SPI_NAND 变体 = 为「烧进板载 NAND、脱离 SD 卡独立运行」而编译；Pico Max 的 SD_CARD 与 SPI_NAND 共用同一 DTS / 物理板（二选一启动）。`Busybox-…-FASTBOOT` 是另一维度：精简 rootfs + 快速启动。

**QA-4：编译产物在哪里？**
均在 Cloud Agent VM 的 `/workspace` 下、全部 gitignored：`output/image/`（最近一次、会被覆盖）、`IMAGE/<板_时间>_RELEASE_TEST/`（每次独立存档）；关键镜像 `update.img`（工具烧录）、`sd_update.img`（写 SD 卡）、`rootfs.img` / `boot.img` / `uboot.img` / `oem.img` / `userdata.img` 等。烧录实体板需取回本地（推荐本地用 `.cursor/Dockerfile.luckfox_pico` 或活动 Dockerfile 重编）。

**QA-5：启动介质与硬件匹配（Pico Max 能插 SD、Ultra W 不能）**
编译选择与硬件完全吻合、无需重编：Pico Max → `SD_CARD`（有卡槽，烧 `sd_update.img` 直写 SD，或 SocToolKit 烧各分区；如需脱卡可另编 `SPI_NAND`）；Ultra W → `EMMC`（板载 eMMC、无卡槽，这也是 Ultra 配置仅 EMMC 的原因，烧录走 USB Type-C 进 MaskROM / Loader + upgrade_tool 烧 `update.img`，其 `sd_update.img` 用不上）。注：Ultra W 无 SPI_NAND 配置（仅 EMMC），只有 Pico Max 有 SPI_NAND 变体。


---

## 12. 参考资料与来源

本设计与实现所依据的一手资料：

- **LUCKFOX 官方《SDK 镜像编译》**（本机编译，方法4 依据）：https://wiki.luckfox.com/zh/Luckfox-Pico-Ultra/SDK-Image-Compilation/
- **LUCKFOX 官方《Docker 环境下编译镜像》**（官方镜像编译，方法5 依据）：https://wiki.luckfox.com/zh/Luckfox-Pico-Ultra/Docker-Image-Build
- **Cursor 官方《Cloud 环境设置 · 运行 Docker》**（Cloud Agent 内 dind：fuse-overlayfs + iptables-legacy）：https://cursor.com/cn/docs/cloud-agent/setup#docker
- **参考 PR（配置即代码模板）**：ESP-Pocket2 #1 https://github.com/yuangezhizao/ESP-Pocket2/pull/1 ；WT9932P4-TINY #2 https://github.com/yuangezhizao/WT9932P4-TINY/pull/2
- **grilling 技能来源**（本会话在环境内安装的辅助技能）：https://github.com/mattpocock/skills/blob/main/skills/productivity/grilling/SKILL.md

## 13. 附录：环境约束与辅助工具

- **以 dev 分支最新文件为准**：本分支基于主线 dev 最新状态；与参考 PR 涉及的同类文件（.cursor/*、AGENTS.md）若在 dev 上有更新，一律以 dev 最新为准（本次已核验 dev 无相关更新）。
- **grilling 辅助技能（不入库）**：本会话按需在环境内安装 grilling 技能到 .cursor/skills/grilling/SKILL.md（用于"拷问式"梳理计划）；它通过 .git/info/exclude 本地忽略、禁止提交到 git，不属于本 PR 交付物。
- **Cloud Agent 模型指定**：.cursor/environment.json 无 model 字段；模型只能经 UI 模型下拉 / Dashboard 默认模型 / Automations / API 指定，且限"支持 Max Mode 的精选模型清单"（详见 §8 与 §11 QA）。
