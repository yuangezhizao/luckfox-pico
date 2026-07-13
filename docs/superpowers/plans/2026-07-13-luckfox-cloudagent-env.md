# Luckfox Pico Cloud Agent 环境 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 用「配置即代码」为 luckfox-pico 添加 Cursor Cloud Agent 支持，使任何人从本分支起 Agent 即得到一致、可复现、开箱即可交叉编译出固件镜像的环境。

**Architecture:** 以 `.cursor/environment.json` 的 Dockerfile 模式固化环境（纯 `build`、无 `install`）。**活动环境**（environment.json 引用的 `.cursor/Dockerfile`）为自建 `ubuntu:24.04`（贴合默认 Cloud Agent 与本机 24.04.4），从裸系统按官方《SDK 镜像编译》apt 清单 + buildroot 硬需依赖自装；**备选环境** `.cursor/Dockerfile.luckfox_pico` 为 Luckfox 官方唯一声明支持的 `luckfoxtech/luckfox_pico:1.0`（Ubuntu 22.04、依赖预装）。两者均 tag+digest 双锁定。编译不需 docker-in-docker：交叉工具链已随仓库内置，Agent 直接在容器内 `./build.sh` 即产出固件。

**Tech Stack:** Cursor Cloud Agent（environment.json / Dockerfile 模式）、Docker、Luckfox Pico SDK（`./build.sh` allsave）、buildroot 2023.02.6、kernel 5.10.160、内置交叉工具链 `arm-rockchip830-linux-uclibcgnueabihf`（gcc 8.3.0）；基线 Ubuntu 24.04（活动）/ 22.04（官方备选）。

---

## 文件结构（File Structure）

| 文件 | 责任 |
| --- | --- |
| `.cursor/environment.json` | Cloud Agent 环境入口：Dockerfile 模式（`{"build":{"dockerfile":"Dockerfile","context":".."}}`），纯 build、无 install |
| `.cursor/Dockerfile` | **活动**环境：自建 `ubuntu:24.04`（tag+digest 双锁定）+ 官方 apt 清单 + buildroot 补齐（`wget patch bzip2 xz-utils perl gzip tar findutils sed`，**不含 which**）+ `curl`/`sudo`/`ca-certificates`/`locales` + git safe.directory；附「平台自动安装包」注释框 |
| `.cursor/Dockerfile.luckfox_pico` | **备选**环境：官方镜像 `luckfoxtech/luckfox_pico:1.0`（Ubuntu 22.04、依赖预装）+ 补 `sudo curl vim less file htop` + git safe.directory；附「平台自动安装包」注释框 |
| `AGENTS.md` | 给 Agent 的仓库说明：中文交互约定、仓库性质、活动/备选环境、非交互选板、构建/验证、编译污染提醒；编译实测数据引 spec §7 |
| `docs/superpowers/specs/2026-07-13-luckfox-cloudagent-env-design.md` | 设计规格（spec） |
| `docs/superpowers/plans/2026-07-13-luckfox-cloudagent-env.md` | 实施计划（本文件） |

**背景常量：**
- 活动基底：`ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90`（当前 digest 实测对应 24.04.4 LTS）
- 官方镜像：`luckfoxtech/luckfox_pico:1.0@sha256:915d44588085826cbeda4b969dbbe7d5e54bf779ba36cda3c5072ee9533e0417`（Docker Hub 仅此一个 tag，2023-11-11 后未更新）
- 官方《SDK 镜像编译》apt 清单（取自 `README.md`）：`git ssh make gcc gcc-multilib g++-multilib module-assistant expect g++ gawk texinfo libssl-dev bison flex fakeroot cmake unzip gperf autoconf device-tree-compiler libncurses5-dev pkg-config bc python-is-python3 passwd openssl openssh-server openssh-client vim file cpio rsync`
- 选板：Pico Max = `printf '4\n0\n0\n' | ./build.sh lunch`；Ultra W = `printf '5\n0\n0\n' | ./build.sh lunch`
- 成功判据：`IMAGE/<板>_RELEASE_TEST/` 出现新存档目录 **且** `./build.sh` 退出码为 0；产物在 `output/image/*.img`

---

## Task 分解与完成情况

### Task 1：`.cursor/environment.json` + 两个 Dockerfile
- **environment.json**：Dockerfile 模式（`build.dockerfile=Dockerfile`、`context=..`），纯 `build`、无 `install`——git「dubious ownership」由 Dockerfile 内 `git config --system --add safe.directory '*'` 一次性解决（`--system` 落镜像层、对所有用户生效）。
- **活动 `.cursor/Dockerfile`**：`FROM ubuntu:24.04@sha256:4fbb8e6a…`，装官方 apt 清单 + buildroot 硬需 `wget patch bzip2 xz-utils perl gzip tar findutils sed` + `curl sudo ca-certificates locales`；**绝不写 `which`**（which 无独立实体包、由 debianutils 内置；24.04 上写它会装上虚包 `gnu-which` 徒增冗余、官方镜像 22.04 上则致 `E: Unable to locate package which`、apt 退出码 100）。
- **备选 `.cursor/Dockerfile.luckfox_pico`**：`FROM luckfoxtech/luckfox_pico:1.0@sha256:915d4458…`，仅补基础镜像缺失项 `sudo curl vim less file htop`（SDK 编译依赖官方镜像已预装）。
- ✅ **完成**：两镜像 `docker build` 均成功、tag+digest 双锁定；活动镜像 digest 与实测验证两板编译的镜像一致。

### Task 2：`AGENTS.md`
- 覆盖：中文交互约定；仓库性质（Luckfox RV1103/RV1106 交叉编译 SDK、非 ESP-IDF、验证=产出固件镜像、无长期服务）；活动/备选环境与解析优先级；交叉工具链内置；非交互选板；构建/验证命令与成功判据；编译污染提醒（`hostapd`/`hostapd_cli`/`librkwifibt.so` 由 `project/app/wifi_app/` 源码重编覆盖跟踪副本，提交前 `git checkout` 恢复）。编译实测数据引 spec §7。
- ✅ **完成**：与 `.cursor/*` 及 spec 最终态一致。

### Task 3：三路径 × 两板编译验证
- 三条路径（本机 apt / 官方 docker 镜像 / 自建 docker 24.04）× 两板（Pico Max `RV1106_Luckfox_Pico_Pro_Max` / Ultra W `RV1106_Luckfox_Pico_Ultra`）= 6 组，每组按 `lunch → clean → lunch → allsave` 执行（`./build.sh clean` 即 `clean all`、会删除 `.BoardConfig.mk`，故 clean 后须重新非交互 `lunch` 才能全量编译）。
- ✅ **完成**：6/6 成功（退出码 0 + `_RELEASE_TEST` 新存档 + `output/image/*.img`）。耗时口径见 spec §7.3（clean 全量、**含 buildroot 联网下载**、native 与 docker 非同批次，故仅供粗参）。
- ✅ **SPI_NAND 补测（2026-07-16，三路径铺满）**：上述 6 组 Pico Max 用 SD_CARD 介质；另对 Pico Max **SPI_NAND** 介质在三条路径各实编一次（clean 全量，`allsave` 耗时 native **26m6s** / 官方 docker **28m12s** / 自建 docker **27m1s**），**均退出码 0**、各出一份存档（`…20260716.0924/2233/2305…`）；三者产物字节大小一致：`rootfs.img`(UBI)**≈52.5MiB**（放进 210MB 分区余量约 75%）、`update.img`≈78MiB、`oem.img`≈19.1MiB。docker 两路径编后已 `chown` 复原属主并 `git checkout` 复原跟踪件。详见 spec §7.3.1 / §11.1 Q12。
- 目标产物由内置交叉工具链（gcc **8.3.0**）/ kernel **5.10.160** / buildroot **2023.02.6** 决定，三路径**功能预期一致**（基于相同构建输入的推断；本次仅验证「编译成功 + 组件版本一致」，**未做板上启动 / 外设回归**；非字节一致，buildroot / U-Boot 内嵌构建时间戳）。

### Task 4：设计规格 spec + 本 plan
- 按 superpowers 规范撰写 spec（目标 / 需求 / 设计决策 / 三方案对比 / 板型映射 / 验证 / 关键发现 / QA / 参考资料）与本 plan。
- ✅ **完成**。
> 提示注入攻防复盘按维护者要求移至 **PR 评论**、不入库（`docs/superpowers/` 仅保留 superpowers 标准产物 specs/plans）。

---

## 完成情况总结

| 交付物 | 状态 |
| --- | --- |
| `.cursor/environment.json` + 活动 `Dockerfile`(24.04) + 备选 `Dockerfile.luckfox_pico`(官方镜像) | ✅ |
| `AGENTS.md` | ✅ |
| 三路径 × 两板编译验证（6/6） | ✅ |
| spec + plan | ✅ |

**整体结论**：Cloud Agent 环境「配置即代码」已交付并实测通过——活动自建 ubuntu24 + 官方镜像备选 + 本机 apt 对照，三路径对 Luckfox Pico Max（SD_CARD）与 Luckfox Ultra W（EMMC）全部编译成功、产物功能预期一致（编译层面验证，未做板上回归）；spec 与 plan 定稿。

---

## 设计演进摘要

本 plan 已直接呈现最终态；下列为达成最终态过程中的关键决策与理由，便于回溯（详见 spec 对应章节）：

- **活动基底选 Ubuntu 24.04（而非官方 22.04 镜像）**：为开箱贴合默认 Cloud Agent 与本机（均 24.04.4）、少维护一版；已实测两板可编、产物与官方功能预期一致（未板上验证）。官方 22.04 镜像保留为「受官方支持」的一键可切备选（改 environment.json 的 `dockerfile` 指向）。详见 spec §4.1 / §4.5 / Q11。
- **自建镜像依赖坑固化**：官方 apt 清单遗漏 buildroot 硬需的 `wget`/`patch`；`which` 无独立实体包（24.04 写它会装上虚包 gnu-which 徒增冗余、官方镜像 22.04 直接 apt 退出码 100）——已固化为可复现清单（补 wget/patch 等、绝不含 which）。详见 spec §8。
- **两 Dockerfile 对齐参考仓库格式**：参照 ESP-Pocket2#1 / WT9932P4-TINY#2，补文件头注释与「平台自动安装包」注释框。
- **注入攻防复盘移出仓库**：superpowers 目录仅含 specs/plans，故该复盘移至 PR 评论。
- **据实修正（避免过度声称）**：`dl/` 不随仓库（rootfs 首次 / clean 后需联网下载）；耗时表为 clean 全量、含下载、native 与 docker 非同批次，仅供粗参；官方镜像缺 `curl` 影响的是 buildroot 构建初的镜像测速（缺则回落上游站点、偏慢），并非「每包 curl→wget 重试」；`librkwifibt.so` 由源码编译（非厂商 blob）；三路径产物「功能预期一致（未板上验证）」而非「字节一致」。详见 spec §4.4 / §7.3 / §8 / §9。
- **补充使用答疑（spec §11）**：Q12 = Pico Max 烧板载 SPI NAND、免插 SD 卡（容量 / UBIFS / oem 分流 / 烧录）；Q13 = Buildroot vs Busybox 选型。
