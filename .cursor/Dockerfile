# Luckfox Pico SDK — Cloud Agent 环境镜像（自建 Ubuntu 24.04 方案 / 当前活动，environment.json 引用本文件）
#
# 目标：把开发环境「代码化」，不依赖任何人的个人快照（Personal snapshot）；任何人从带本文件的分支起 Cloud Agent，都能得到可复现的交叉编译环境，让 `./build.sh` 开箱即用。
#
# 说明：
# - Cloud Agent 本身就运行在「一个容器」里；本 Dockerfile 只是「声明这个容器长什么样」，并非 docker-in-docker。未来要装 Tailscale / cloudflared，直接在本文件里 apt 安装或下载二进制、运行时按官方 userspace 方式启动即可。
# - 基于 ubuntu:24.04（贴合默认 Cloud Agent 与本机的 24.04.4 LTS）：从裸系统按官方《SDK 镜像编译》apt 清单 + buildroot 硬需自装 SDK 全部编译依赖。⚠️ 官方仅声明支持 Ubuntu 22.04，24.04 超出官方支持范围，但已实测 Pico Max 与 Ultra W 两板均编译成功（host gcc13/glibc2.39；目标产物与官方 22.04 镜像一致，因交叉工具链内置于仓库）。备选的官方 22.04 镜像见 .cursor/Dockerfile.luckfox_pico。
# - ARM 交叉工具链 arm-rockchip830-linux-uclibcgnueabihf（gcc 8.3.0）已随 SDK 仓库内置于 tools/linux/toolchain/，build.sh 选板后自动加入 PATH，无需在镜像内安装。
# - ubuntu:24.04 是 Ubuntu based，满足 Cursor computer use（Desktop）对 Debian/Ubuntu 的要求。
# - 不要 COPY 项目源码：Cursor 会自行 checkout 正确的 commit 到工作区。
# - FROM 同时锁定 tag 与 digest：tag（24.04）便于人读，digest 保证镜像内容字节级不可变（同一 tag 可被重推、digest 不会）。更新方式：docker buildx imagetools inspect ubuntu:24.04（取 index digest）；当前 digest 实测对应 24.04.4 LTS、与裸机 VM 一致。
FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

# DEBIAN_FRONTEND=noninteractive：告诉 apt「无人值守」，安装期不弹交互配置对话（典型如 tzdata 选时区、keyboard-configuration），避免 docker build 卡在等待输入而失败/挂起。仅构建期需要，故用 ARG（构建变量、对后续 RUN 生效但不写入最终镜像），避免用 ENV 持久化到运行期改变交互式 apt 行为（Docker 官方建议）。
ARG DEBIAN_FRONTEND=noninteractive
# TZ：预设时区，配合 noninteractive 让 tzdata 非交互安装；亦影响容器内 date 与编译存档时间戳（如 IMAGE/*_RELEASE_TEST 命名）。运行期仍需该时区，故保留 ENV 持久化。
ENV TZ=Asia/Shanghai

# ┌─ 平台会「自动安装」的包（无需在本文件重复安装）──────────────────────────────
# │ Cursor 每次启动都会跑桌面初始化，按容器内 /usr/local/share/vnc-desktop.Aptfile
# │ 用 `apt-get install --no-install-recommends` 安装下列（实测 sha256=819987b7…，与本仓 2026-07-14 环境一致）：
# │   VNC     : tigervnc-standalone-server tigervnc-common tigervnc-tools
# │   XFCE    : xfce4 xfce4-terminal xfce4-settings thunar
# │   X11     : x11-utils x11-xserver-utils xdg-utils xdotool xclip procps
# │   D-Bus   : dbus-x11 at-spi2-core
# │   应用    : mousepad seahorse sudo ffmpeg
# │   主题    : adwaita-icon-theme gnome-themes-extra gnome-keyring plank sassc libglib2.0-dev-bin libxml2-utils dconf-cli xz-utils
# │   locale  : locales
# │   字体    : fonts-noto fonts-wqy-microhei fonts-droid-fallback fonts-noto-color-emoji fonts-liberation fonts-croscore fonts-cantarell fonts-jetbrains-mono xfonts-base xfonts-terminus
# │   桌面库  : libx11-dev libxkbfile-dev libsecret-1-dev libgbm-dev libnotify4 libnss3 libxss1 libgl1-mesa-dri libglx-mesa0 libgl1
# │   Python  : python3-minimal python3-numpy
# │   资产依赖: bash ca-certificates coreutils curl findutils gzip tar
# │   浏览器  : google-chrome-stable（单独脚本 install-google-chrome 安装）
# │ 另外平台还会：把 gh 软链到 /usr/local/bin/gh、配置 git 身份与 SSH 提交签名、每次启动 git clean -fd 并重建 /opt/cursor/artifacts。
# │ ⚠️ 本仓是纯交叉编译 SDK、不用桌面 computer use，但平台仍会装上述包；维护提示（清单实测 2026-07-14）：若平台不再自动装致编译/工具异常，把缺的项补进下面 apt。
# └──────────────────────────────────────────────────────────────────────────────

# 从裸 Ubuntu 24.04 自装 SDK 全部编译依赖（官方《SDK 镜像编译》apt 清单 + buildroot 硬需补齐）：
# - 编译依赖属「核心功能」：虽平台 Aptfile 已含 sudo/curl/ca-certificates/locales/xz-utils/findutils/gzip/tar 等，但为「不依赖官方镜像、也不依赖运行时平台行为」而在镜像层完整固化自列（保证构建可复现）。
# - buildroot 硬需但官方 apt 清单遗漏：wget、patch（平台 Aptfile 亦不含）；缺则 rootfs 阶段报 "You must install wget / GNU patch"。
# - 绝不写 which：which 无独立实体包（命令由 essential 包 debianutils 内置、基础镜像已自带）；ubuntu:24.04（universe 默认开启）上写它会解析到虚包 gnu-which 并安装成功（退出 0）、徒增冗余包，官方镜像 Ubuntu 22.04 上则报 "E: Unable to locate package which" 致退出码 100——两种情况都不该写。
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ssh make gcc gcc-multilib g++-multilib module-assistant expect g++ gawk \
      texinfo libssl-dev bison flex fakeroot cmake unzip gperf autoconf \
      device-tree-compiler libncurses5-dev pkg-config bc python-is-python3 passwd \
      openssl openssh-server openssh-client vim file cpio rsync curl \
      wget patch bzip2 xz-utils perl gzip tar findutils sed \
      sudo ca-certificates locales \
    && rm -rf /var/lib/apt/lists/*

# 允许对检出的工作区执行 git（避免 "detected dubious ownership" 报错）。
RUN git config --system --add safe.directory '*'
