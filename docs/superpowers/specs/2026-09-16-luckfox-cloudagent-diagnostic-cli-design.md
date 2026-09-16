# Luckfox Pico Cloud Agent 诊断 CLI 软件包设计规格（Design Spec）

- **日期**：2026-09-16
- **状态**：已 Review
- **分支**：`cursor/dockerfile-user-ubuntu-1fe9`（起点 `origin/dev`，含已合入的 PR #9）
- **主题**：在 Cloud Agent 宿主镜像中补装一组诊断 / 网络排查 CLI，供会话与 SSH 排障使用
- **关联代码文件**：`.cursor/Dockerfile`、`.cursor/Dockerfile.luckfox_pico`
- **关联计划**：[`2026-09-16-luckfox-cloudagent-diagnostic-cli.md`](../plans/2026-09-16-luckfox-cloudagent-diagnostic-cli.md)
- **关联规格**：[`2026-07-13-luckfox-cloudagent-env-design.md`](2026-07-13-luckfox-cloudagent-env-design.md)、[`2026-08-30-luckfox-cloudagent-tailscale-design.md`](2026-08-30-luckfox-cloudagent-tailscale-design.md)、[`2026-09-14-luckfox-cloudagent-default-user-design.md`](2026-09-14-luckfox-cloudagent-default-user-design.md)

---

## 1. 概述与目标

Cloud Agent 活动镜像已能交叉编译固件，并带有 `htop` / `neofetch` / `iproute2` / `jq` / `tcpdump`。本规格在同一套「配置即代码」路径上，再补一组宿主侧诊断 CLI，使 Agent 会话与 Tailscale SSH 登录后不必临时 `apt-get`。

达成后：

1. 从含本变更的 Environment Build 冷启动的 Agent 上，§2.2 表中每个 **Ubuntu 包名** 已安装，对应命令在 `PATH` 中。
2. 活动镜像（`.cursor/Dockerfile`）与备选镜像（`.cursor/Dockerfile.luckfox_pico`）清单一致；把 `environment.json` 的 `dockerfile` 指到备选时，这组工具仍在。
3. 默认会话用户仍是 `ubuntu`；包写在全部 `USER` 之前的 apt `RUN` 里，不改 `environment.json`、`install.sh`、`start.sh`、`./build.sh` 或板上 rootfs。

**不在本规格范围**：把这些工具编进 Luckfox 固件；在仓库里增加扫描脚本、payload 或攻击步骤；安装 `conntrackd` / `iotop-c` / `ncat` / `zenmap`；给 `ubuntu` 设登录密码；把 Docker 引擎写入本仓 Dockerfile。

---

## 2. 设计决策

### 2.1 落点：公开 Dockerfile，不进 install / start

| 方案 | 做法 | 结论 |
| --- | --- | --- |
| A. 两份 Dockerfile 的 SDK/工具 apt `RUN`（采用） | 与现有 `htop` / `neofetch` 同一层、`--no-install-recommends`、`USER ubuntu` 之前 | 工具进入可审计的公开镜像层与 Environment Build 快照；切备选指针不丢工具 |
| B. `.cursor/install.sh` | Build 期再 `apt-get` | 否决。`install.sh` 只承担 grilling 与 `openssh-server` 私有快照；诊断 CLI 不是密钥材料，不应与 host key 混层 |
| C. `.cursor/start.sh` 每次启动安装 | 每 Run 联网装包 | 否决。拉长启动，且违反「依赖进 Dockerfile / 每 boot 只做运行时」分层 |

只改活动 Dockerfile、不改备选：否决。现有排查 CLI（`htop` / `neofetch` / `tcpdump`）已是双文件；只改活动会使切官方 22.04 备选后缺工具。

不另开一层只装这组包的 `RUN`：否决。多一次 `apt-get update` 与一层缓存，收益只是「与 SDK 编译依赖视觉分离」。

### 2.2 AlmaLinux 包名 → Ubuntu apt 包名

对照列用 **AlmaLinux 9** 的 RPM 名（与用户给出的清单同一套命名）。Cloud Agent 宿主是 Ubuntu，Dockerfile 只写右列 apt 名，不引入 AlmaLinux / EPEL 仓库。

Ubuntu / Debian **没有**名为 `conntrack-tools` 的实体包。AlmaLinux 9 AppStream 的 `conntrack-tools` 一个 RPM 内含 `conntrack` 与 `conntrackd`。2026-09-16 在本活动环境（Ubuntu 24.04.4 noble）`apt-cache show`：`conntrack` 的 `Source:` 为 `conntrack-tools`，提供 `conntrack` 命令；`conntrackd` 是另一个 apt 包。Dockerfile 只写 **`conntrack`**，不装 `conntrackd`。

`iotop` 取 Python 包 `iotop`（AlmaLinux 9 BaseOS 亦为 `iotop`，无 `iotop-c`），不取 `iotop-c`。`psmisc` 提供 `pstree` / `fuser` / `killall`，不是名为 `psmisc` 的命令。

AlmaLinux 仓库归属以 2026-09-16 拉取的 AlmaLinux 9.8 x86_64 `primary.xml` 为准：`tree` / `iotop` / `traceroute` / `psmisc` / `dmidecode` 在 BaseOS；`nmap` / `conntrack-tools` 在 AppStream。`iftop` / `screen` / `ncdu` / `ngrep` / `fping` 不在 BaseOS/AppStream/CRB，EPEL 9 上 RPM 名仍是这些字符串。无名为 `conntrack` 或 `conntrackd` 的独立 AlmaLinux 官方包。

| AlmaLinux 包名 | Ubuntu apt 包名 | 验收命令 | Section（noble） |
| --- | --- | --- | --- |
| tree | `tree` | `tree` | universe/utils |
| iftop | `iftop` | `iftop` | universe/net |
| iotop | `iotop` | `iotop` | admin |
| screen | `screen` | `screen` | misc |
| ncdu | `ncdu` | `ncdu` | universe/admin |
| traceroute | `traceroute` | `traceroute` | universe/net |
| nmap | `nmap` | `nmap` | universe/net |
| ngrep | `ngrep` | `ngrep` | universe/net |
| conntrack-tools | `conntrack` | `conntrack` | net |
| psmisc | `psmisc` | `pstree` | admin |
| fping | `fping` | `fping` | universe/net |
| dmidecode | `dmidecode` | `dmidecode` | utils |

`nmap` / `ngrep` 与已装的 `neofetch` 同属 universe。备选 Jammy 官方 FROM 已能装 `neofetch`，不为此单独 `add-apt-repository`。

FROM 去重沿用既有规则：只看锁定 digest 的 `dpkg`，已在 FROM 则不写。2026-09-06 `ubuntu:24.04@sha256:4fbb8e6a…` 的 92 个包（含 `procps`，不含 `psmisc` 与上表其余包）；官方 luckfox digest 的 366 个包同样不含这组（与 `htop` 同批「FROM 没有则显式装」）。实现时若复核 `dpkg-query` 发现某包已在 FROM，从 Dockerfile 去掉该名，不改本表验收命令。

不锁 apt 版本（与 SDK/工具层、Tailscale 层一致）。`--no-install-recommends` 继续生效：不把 nmap 的 Suggests（`ncat` / `ndiff` / `zenmap`）写成硬依赖。

### 2.3 `USER ubuntu` 与能力边界

包必须写在两份文件里 **全部 `RUN` 之后、`USER ubuntu` 之前** 的那条 SDK/工具 apt `RUN`（备选文件即现有 `sudo curl locales` / `htop neofetch` / `iproute2 jq tcpdump` 那条）。禁止在 `USER` 之后再加 apt `RUN`（构建期没有 `sudo -n -E`，非 root 写 `/var/lib/apt` 会失败，见 2026-09-14 spec）。

会话用户是 `ubuntu`，免密 sudo 已有。`iftop` / `iotop` / `nmap` / `ngrep` / `conntrack` / `dmidecode` 常需 root 或 `CAP_NET_RAW` / `CAP_NET_ADMIN`；验收只要求包与命令存在，不要求无 sudo 就能抓到接口或读到 SMBIOS。容器内 `dmidecode` 常报无 DMI entry，不列为失败。

本规格只把发行版包装进 **宿主** 镜像供本机排障；不在仓库中增加扫描脚本或攻击步骤。

### 2.4 文档与 AGENTS.md

合入时：两份 Dockerfile 注释补一句（与 `htop` / `neofetch` 并列）；[`2026-08-30` §2.3.1](2026-08-30-luckfox-cloudagent-tailscale-design.md) 需求集合补上这 12 个 apt 包名；[`2026-07-13` §10](2026-07-13-luckfox-cloudagent-env-design.md) 交付物表不枚举包名，只保留「排查 CLI」指针。`AGENTS.md` **不**列出这 12 个包。

改写本功能分支并推送前，相对 `origin/dev` 必须已有独有提交；若分支与 `dev` 无 diff 就推送，GitHub 会关闭以 `dev` 为 base 的 PR。

---

## 3. 需求

### 3.1 功能需求

| 编号 | 需求 |
| --- | --- |
| F1 | 活动与备选 Dockerfile 的 SDK/工具 apt `RUN` 均包含 §2.2 的 12 个 apt 包名（若复核 FROM 已有则省略该名），且该 `RUN` 位于 `USER ubuntu` 之前 |
| F2 | 含本 Dockerfile 的 Environment Build `SUCCEEDED` 后冷启动，`dpkg-query -W` 对这 12 个包名为 `install ok installed`，§2.2 验收命令 `command -v` 成功 |
| F3 | 不修改 `environment.json`、`install.sh`、`start.sh`；不在 `USER` 之后增加 apt `RUN` |
| F4 | 合入时按 §2.4 更新 Dockerfile 注释与 2026-08-30 §2.3.1；不把包名写入 `AGENTS.md` |

### 3.2 非功能需求

| 编号 | 需求 |
| --- | --- |
| N1 | `--no-install-recommends`；不锁版本；禁止写入 `which` / `gnu-which` / `conntrack-tools` / `conntrackd` / `iotop-c` |
| N2 | 不改变 2026-09-14 的默认用户 `ubuntu` 与 `sudo -n -E` 包装；不把诊断工具编进目标固件 |
| N3 | 不引入明文凭据、扫描脚本或攻击步骤 |

---

## 4. 目标 Dockerfile 片段

活动与备选在现有 `htop neofetch` 行之后追加同一组包名（备选若某名已在 FROM 则去掉）。示意：

```dockerfile
      iproute2 jq tcpdump \
      htop neofetch \
      tree iftop iotop screen ncdu traceroute \
      nmap ngrep conntrack psmisc fping dmidecode \
```

注释增加一条：诊断 CLI（`tree` / `iftop` / `iotop` / `screen` / `ncdu` / `traceroute` / `nmap` / `ngrep` / `conntrack`（AlmaLinux 包名 `conntrack-tools`）/ `psmisc` / `fping` / `dmidecode`）；`nmap`/`ngrep`/`ncdu` 等在 universe，与 `neofetch` 相同前提。

---

## 5. 验证策略

验收必须使用 snapshot 已含本规格 Dockerfile 的 Build 冷启动；当前仍基于旧快照的 Agent 不能当反例。实现前在 active Build [`bld-20260916-cac6cb9d-2b58-45e1-86f5-e19da08d54aa`](https://cursor.com/dashboard/cloud-agents/builds/bld-20260916-cac6cb9d-2b58-45e1-86f5-e19da08d54aa) 上的基线（12 个包均未安装）见 plan「当前 Agent 基线」。不要求为此重跑 `./build.sh allsave`。

| 步骤 | 通过标准 |
| --- | --- |
| V1 包 | `dpkg-query -W -f='${Package} ${Status}\n' tree iftop iotop screen ncdu traceroute nmap ngrep conntrack psmisc fping dmidecode` 均为 `install ok installed` |
| V2 命令 | `command -v` 对 `tree iftop iotop screen ncdu traceroute nmap ngrep conntrack pstree fping dmidecode` 均成功 |
| V3 分层 | `environment.json` / `install.sh` / `start.sh` 相对本功能起点无 diff；两份 Dockerfile 最后非空指令仍为 `USER ubuntu` |
| V4 包名 | 任一份 Dockerfile 的 apt 清单都不含 `conntrack-tools`、`conntrackd`、`iotop-c`、`which`、`gnu-which` |
| V5 Build | 目标 Environment Build 为 `SUCCEEDED` |

---

## 6. 风险与约束

| 风险 | 缓解 |
| --- | --- |
| 写成 `conntrack-tools` | apt 找不到包，Build 退出 100；清单只写 `conntrack` |
| `USER` 之后再 apt | 非 root 安装失败；只改 `USER` 之前现有 `RUN` |
| 只改活动 Dockerfile | 切备选缺工具；两份都改 |
| 无独有提交就推送功能分支 | GitHub 关闭以 `dev` 为 base 的 PR；有相对 `origin/dev` 的 commit 再推 |
| 容器内无 DMI / 缺 net cap | 不把 `dmidecode` 读表或 `iftop` 出流量图列为 V1/V2 |
| nmap/ngrep 能力 | 仅宿主诊断；仓库不增加扫描脚本 |

---

## 7. QA 记录

本节只收录 grilling 已闭合的决策；同一主题并入原条目、不新开编号。

| ID | 问题 | 用户选择 | 备注 |
| --- | --- | --- | --- |
| Q1 | 改几份 Dockerfile | 活动 `.cursor/Dockerfile` 与备选 `.cursor/Dockerfile.luckfox_pico` 都改 | 见 §2.1 |
| Q2 | 文档改到哪 | Dockerfile 注释 + `2026-08-30` §2.3.1 需求集合；`AGENTS.md` 不列这 12 个包 | 见 §2.4 |
| Q3 | 本 PR 是否打 Environment Build 验收 | 触发 draft Environment Build，冷启动跑 V1/V2/V5 | 见 §5 |

---

## 8. 后续

实现步骤、Environment Build 命令与实测数值见 [`2026-09-16-luckfox-cloudagent-diagnostic-cli.md`](../plans/2026-09-16-luckfox-cloudagent-diagnostic-cli.md)。
