# Luckfox Pico Ultra（eMMC）480×480 RGB 屏点亮实施计划（Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 关闭 `CONFIG_DTC_SYMBOLS`，消除 `backlight` 节点被分配 phandle 导致 `pwm_bl` 开机保持熄灭的缺陷，使自编译固件在 LP40-480480-ARK 屏上的表现对齐官方 260604。

**Architecture:** 改动只有一行 defconfig。验证分三层收敛：先用内核自带 dtc 在 `/tmp` 离线重编设备树，把「改动是否产出与官方逐字节相同的 DTB」这一核心问题在几秒内答完；再由 CI 编译三个板型组合确认无构建回归；最后刷入实体板按 spec §8 判据端到端确认屏幕真的亮。

**Tech Stack:** Linux 5.10.160 内核 defconfig / 内核自带 dtc（`scripts/dtc`）/ GitHub Actions（`build-luckfox-pico-firmware.yml`）/ `upgrade_tool` + ADB。

**关联 spec：** [`docs/superpowers/specs/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604-design.md`](../specs/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604-design.md)

## Global Constraints

- 修复落点限于 SDK 源码 / BoardConfig / defconfig（spec §5.1 方案 A）。**不实施** spec §5.2 的 rootfs overlay 补偿脚本，除非方案 A 无法落地。
- **不得**在自编译固件中混入官方预编译分区——那会破坏「整仓可从源码复现」这一前提。
- 覆盖范围仅 Ultra（eMMC）+ 480×480 屏；720×720 屏与 86Panel 无实物，列为已知未验证项，不做验证承诺。
- 离线验证的一切中间产物（dtc 构建、预处理 DTS、DTB）只允许落在 `/tmp`，**不得污染仓库工作区**。
- 提交信息用 Conventional + gitmoji（`git cz` 风格），subject 单一主题；spec 与 plan 两份文档留到 PR 的**最后一次提交**。本仓提交由环境自动附加一条 `Co-authored-by: Cursor <cursoragent@cursor.com>` trailer，既有 7 个提交均如此，属既定惯例，**不要为去掉它而 amend**。
- 本仓工作区存在一批与本计划无关的**既有**改动（`sysdrv/source/kernel/net/netfilter/` 与 `include/uapi/linux/netfilter*` 下约 21 个文件，以及若干 `.DS_Store` 未跟踪文件）。它们在本计划开始前就已存在，**不要动、不要恢复、不要提交**；判断工作区是否干净时一律按路径限定检查，不要用不带路径的 `git status` / `git diff` 下结论。
- 工作分支 `cursor/luckfox-pico-ultra-emmc-rgb-align-260604`（起点 `dev`）。

## File Structure

| 文件 | 动作 | 职责 |
| --- | --- | --- |
| `sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig` | 修改第 201 行 | 唯一的功能性改动：关闭 `CONFIG_DTC_SYMBOLS` |
| `docs/superpowers/specs/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604-design.md` | 已存在，Task 4 提交 | 设计规格 |
| `docs/superpowers/plans/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604.md` | 本文件，Task 4 提交 | 实施计划 |

离线验证脚本**有意不入库**：它属一次性核查工具，spec §5.1 的落点范围未包含新增仓库工具，加进来会构成范围外改动。所需命令在 Task 1 中逐条给全，可随时重放。

---

### Task 1: 应用 defconfig 改动并用离线重编验证设备树

**Files:**
- Modify: `sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig:201`

**Interfaces:**
- Consumes: 无
- Produces: 供 Task 2 校验 CI 产物用的两个基准值——修复后 DTB 体积 `41740` 字节、SHA256 `60e6928362602b44f6884e9e5f0b20996f23574db4d29bfed378809670e15cfa`

- [ ] **Step 1: 构建内核自带的 dtc（含 Rockchip 裁剪检查），全程在 `/tmp`**

上游 dtc 不认识 `-Wnode_disabled` / `-Wnode_empty` 这两个 Rockchip 私有检查，必须用内核树里的这份。

```bash
K=/Users/yuangezhizao/Documents/IDF/luckfox-pico/sysdrv/source/kernel
rm -rf /tmp/dtcbuild && mkdir -p /tmp/dtcbuild && cd /tmp/dtcbuild
cp -R "$K/scripts/dtc" . && cd dtc
bison -o dtc-parser.tab.c -d dtc-parser.y
flex -o dtc-lexer.lex.c dtc-lexer.l
echo '#define DTC_VERSION "DTC 1.6.0-local"' > version_gen.h
gcc -O2 -DNO_YAML -I. -Ilibfdt -o dtc-kernel \
  dtc.c flattree.c fstree.c data.c livetree.c treesource.c srcpos.c checks.c util.c \
  dtc-lexer.lex.c dtc-parser.tab.c libfdt/*.c
./dtc-kernel --version
```

期望：打印 `Version: DTC 1.6.0-local`，`/tmp/dtcbuild/dtc/dtc-kernel` 存在。

- [ ] **Step 2: 写下离线检查命令，并在改动前运行一次，确认缺陷可复现**

该脚本按 defconfig 里 `CONFIG_DTC_SYMBOLS` 的实际取值决定是否传 `-@`，因此它同时是回归检查。

```bash
cat > /tmp/dtbcheck.sh <<'EOF'
#!/bin/bash
set -e
K=/Users/yuangezhizao/Documents/IDF/luckfox-pico/sysdrv/source/kernel
DEFCONFIG=$K/arch/arm/configs/luckfox_rv1106_linux_defconfig
DTS=$K/arch/arm/boot/dts/rv1106g-luckfox-pico-ultra.dts
cd /tmp/dtcbuild
if grep -q '^CONFIG_DTC_SYMBOLS=y' "$DEFCONFIG"; then SYM=-@; echo "defconfig: DTC_SYMBOLS=y  → dtc 传 -@"; else SYM=; echo "defconfig: DTC_SYMBOLS 未设置 → dtc 不传 -@"; fi
gcc -E -nostdinc -I"$K/scripts/dtc/include-prefixes" -I"$K/arch/arm/boot/dts" -I"$K/include" \
  -undef -D__DTS__ -x assembler-with-cpp -o pre.dts "$DTS"
./dtc/dtc-kernel -O dtb -o out.dtb -b 0 \
  -i"$K/arch/arm/boot/dts/" -i"$K/scripts/dtc/include-prefixes" \
  $SYM -Wnode_disabled -Wnode_empty pre.dts 2>/dev/null
echo "DTB 体积 : $(stat -f%z out.dtb) B"
echo "DTB SHA  : $(shasum -a 256 out.dtb | cut -d' ' -f1)"
dtc -I dtb -O dts out.dtb 2>/dev/null > out.dts
echo -n "__symbols__ : "; grep -q '__symbols__' out.dts && echo 有 || echo 无
python3 - out.dts <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'^[ \t]*(?:[\w-]+[ \t]*:[ \t]*)?backlight \{(.*?)^[ \t]*\};', s, re.S | re.M)
if not m:
    print("backlight phandle : 节点缺失")
else:
    p = re.search(r'phandle = <([^>]*)>', m.group(1))
    print("backlight phandle :", p.group(1) if p else "无")
PYEOF
EOF
chmod +x /tmp/dtbcheck.sh
/tmp/dtbcheck.sh
```

期望（改动前，缺陷态）：

```
defconfig: DTC_SYMBOLS=y  → dtc 传 -@
DTB 体积 : 76708 B
DTB SHA  : 70da0b6a1f98acdc7e64e2d986103323e838c2809086e035466dce2142c6d1f5
__symbols__ : 有
backlight phandle : 0x164
```

该 SHA 与 CI 产出的 `boot.img` 内 `fdt` 逐字节相同，说明离线复现流程与 CI 构建等价。若体积或 SHA 对不上，**先排查环境再往下走**，不要改 defconfig。

- [ ] **Step 3: 改 defconfig**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
sed -n '199,204p' sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig
```

确认第 201 行是 `CONFIG_DTC_SYMBOLS=y` 后，把该行改为：

```
# CONFIG_DTC_SYMBOLS is not set
```

同区块的 `CONFIG_OF_OVERLAY=y`（202 行）与 `CONFIG_OF_DTBO=y`（203 行）**保持不动**——官方同样开启，`luckfox-config` 的运行时 overlay 依赖它们。

- [ ] **Step 4: 再次运行离线检查，确认与官方 260604 逐字节相同**

```bash
/tmp/dtbcheck.sh
```

期望（改动后）：

```
defconfig: DTC_SYMBOLS 未设置 → dtc 不传 -@
DTB 体积 : 41740 B
DTB SHA  : 60e6928362602b44f6884e9e5f0b20996f23574db4d29bfed378809670e15cfa
__symbols__ : 无
backlight phandle : 无
```

再与官方固件直接比对一次（`/Users/yuangezhizao/Downloads/Luckfox_Pico_Ultra_EMMC_260604/` 需已解压）：

```bash
python3 - <<'PY'
import struct, subprocess, re, hashlib
p='/Users/yuangezhizao/Downloads/Luckfox_Pico_Ultra_EMMC_260604/boot.img'
d=open(p,'rb').read(); hs=struct.unpack('>I', d[4:8])[0]
open('/tmp/h.dtb','wb').write(d[:hs])
hdr=subprocess.check_output(['dtc','-I','dtb','-O','dts','/tmp/h.dtb'],stderr=subprocess.DEVNULL).decode()
num=lambda s,k:int(re.search(rf'{s} \{{[^}}]*{k} = <(0x[0-9a-f]+)>',hdr,re.S).group(1),16)
off,sz=num('fdt','data-position'),num('fdt','data-size')
print('官方 260604 DTB :', sz, 'B', hashlib.sha256(d[off:off+sz]).hexdigest())
print('本地重编 DTB    :', len(open('/tmp/dtcbuild/out.dtb','rb').read()), 'B', hashlib.sha256(open('/tmp/dtcbuild/out.dtb','rb').read()).hexdigest())
PY
cmp -s /tmp/dtcbuild/out.dtb <(python3 -c "
import struct,subprocess,re,sys
p='/Users/yuangezhizao/Downloads/Luckfox_Pico_Ultra_EMMC_260604/boot.img'
d=open(p,'rb').read(); hs=struct.unpack('>I',d[4:8])[0]
open('/tmp/h.dtb','wb').write(d[:hs])
hdr=subprocess.check_output(['dtc','-I','dtb','-O','dts','/tmp/h.dtb'],stderr=subprocess.DEVNULL).decode()
num=lambda s,k:int(re.search(rf'{s} \{{[^}}]*{k} = <(0x[0-9a-f]+)>',hdr,re.S).group(1),16)
o,s=num('fdt','data-position'),num('fdt','data-size')
sys.stdout.buffer.write(d[o:o+s])") && echo "✅ 与官方 260604 DTB 逐字节相同" || echo "❌ 不同，停止并排查"
```

期望：两行 SHA 相同，且打印 `✅ 与官方 260604 DTB 逐字节相同`。

- [ ] **Step 5: 确认工作区只有这一处改动，然后提交**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
git diff --stat -- sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig
git diff sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig
git status --short -- project/app/wifi_app/
```

期望：defconfig 显示 `1 insertion(+), 1 deletion(-)`，diff 内容正好是 `CONFIG_DTC_SYMBOLS=y` → `# CONFIG_DTC_SYMBOLS is not set`；`project/app/wifi_app/` 下无输出。

**注意**：本仓工作区存在一批与本任务无关的既有改动（`sysdrv/source/kernel/net/netfilter/` 与 `include/uapi/linux/netfilter*` 下约 21 个文件，以及若干 `.DS_Store` 未跟踪文件），它们在本任务开始前就已存在，**不要动、也不要提交**。因此只按上面的路径限定命令检查，不要用不带路径的 `git diff --stat` 判断「工作区只有一处改动」。若 `project/app/wifi_app/` 下出现 `hostapd` / `hostapd_cli` / `librkwifibt.so` 被改写，用 `git checkout -- <file>` 恢复后再提交。

```bash
git add sysdrv/source/kernel/arch/arm/configs/luckfox_rv1106_linux_defconfig
git commit -m "$(cat <<'EOF'
fix(kernel): 🐛 关闭 CONFIG_DTC_SYMBOLS 以修复 RGB 屏背光开机不亮

- dtc 的 -@ 会给所有带 label 的节点生成 phandle，backlight 节点因此拿到 phandle
- pwm_bl 见到 phandle 即认为「另有驱动会点亮背光」而返回 FB_BLANK_POWERDOWN，但 RGB panel 链路上并无该驱动
- 连锁后果是 PWM 从未 enable，pwm-rockchip 也就不会切换 active 引脚状态，GPIO3-27 停在 GPIO 模式、背光无波形
- 本仓无任何标签式 overlay（luckfox-config 全用路径式 target），符号表无人使用；SDK 自带的 tb_defconfig 本来也没开
- ⚠️ 该 defconfig 被 13 个 BoardConfig 共用，全板型 DTB 都会变小，其中仅 Ultra 与 86Panel 含 backlight 节点
- 关闭后本仓源码产出的 DTB 与官方 260604 固件逐字节相同

详见 spec §4、§6
EOF
)"
```

---

### Task 2: CI 三组合编译并校验产物

**Files:**
- 无代码改动；使用既有 `.github/workflows/build-luckfox-pico-firmware.yml`

**Interfaces:**
- Consumes: Task 1 的 defconfig 改动与两个基准值（`41740` / `60e69283…`）
- Produces: artifact `luckfox-pico-firmware_ultra-emmc_on-ubuntu-24.04`，供 Task 3 刷机

- [ ] **Step 1: 推送分支**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
git push -u origin cursor/luckfox-pico-ultra-emmc-rgb-align-260604
```

- [ ] **Step 2: 手动触发 workflow**

该 workflow 的 `push` 触发只监听 `dev` 分支，feature 分支必须走 `workflow_dispatch`。

```bash
gh workflow run build-luckfox-pico-firmware.yml --ref cursor/luckfox-pico-ultra-emmc-rgb-align-260604
sleep 10
gh run list --workflow=build-luckfox-pico-firmware.yml --branch cursor/luckfox-pico-ultra-emmc-rgb-align-260604 --limit 1
```

- [ ] **Step 3: 等待三个组合全部完成**

```bash
RUN_ID=$(gh run list --workflow=build-luckfox-pico-firmware.yml --branch cursor/luckfox-pico-ultra-emmc-rgb-align-260604 --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN_ID"
gh run view "$RUN_ID"
```

期望：`build-image` 与三个 `build-firmware` 组合（`Luckfox Pico Max · SD_CARD`、`Luckfox Pico Max · SPI_NAND`、`Luckfox Pico Ultra W · EMMC`）全部 success。Ultra W 组合冷编约 76 分钟。任一组合失败即停下排查，不要继续刷机。

- [ ] **Step 4: 下载 Ultra EMMC 产物**

```bash
RUN_ID=$(gh run list --workflow=build-luckfox-pico-firmware.yml --branch cursor/luckfox-pico-ultra-emmc-rgb-align-260604 --limit 1 --json databaseId -q '.[0].databaseId')
rm -rf /tmp/ci-ultra && mkdir -p /tmp/ci-ultra
gh run download "$RUN_ID" -n luckfox-pico-firmware_ultra-emmc_on-ubuntu-24.04 -D /tmp/ci-ultra
ls -la /tmp/ci-ultra/output/image/
```

期望：`boot.img` / `uboot.img` / `oem.img` / `rootfs.img` / `update.img` 等齐全。

- [ ] **Step 5: 校验新 `boot.img` 的 DTB 与整体布局**

```bash
python3 - <<'PY'
import struct, subprocess, re, hashlib, os
p='/tmp/ci-ultra/output/image/boot.img'
d=open(p,'rb').read(); hs=struct.unpack('>I', d[4:8])[0]
open('/tmp/h.dtb','wb').write(d[:hs])
hdr=subprocess.check_output(['dtc','-I','dtb','-O','dts','/tmp/h.dtb'],stderr=subprocess.DEVNULL).decode()
num=lambda s,k:int(re.search(rf'{s} \{{[^}}]*{k} = <(0x[0-9a-f]+)>',hdr,re.S).group(1),16)
fo,fs=num('fdt','data-position'),num('fdt','data-size')
ko=num('kernel','data-position')
dtb=d[fo:fo+fs]
print(f'boot.img 总体积 : {len(d)} B        期望 3792896（±内核体积波动）')
print(f'DTB 体积        : {fs} B            期望 41740')
print(f'DTB SHA256      : {hashlib.sha256(dtb).hexdigest()}')
print(f'                  期望 60e6928362602b44f6884e9e5f0b20996f23574db4d29bfed378809670e15cfa')
print(f'kernel 偏移     : {hex(ko)}          期望 0xac00')
dts=subprocess.check_output(['dtc','-I','dtb','-O','dts','-'],input=dtb,stderr=subprocess.DEVNULL).decode()
print('__symbols__     :', '有 ❌' if '__symbols__' in dts else '无 ✅')
bl=re.search(r'^\s*(?:[\w-]+\s*:\s*)?backlight \{(.*?)^\s*\};', dts, re.S|re.M)
print('backlight phandle:', ('有 ❌' if 'phandle' in bl.group(1) else '无 ✅') if bl else '节点缺失 ❌')
PY
```

期望：DTB 41,740 B 且 SHA256 与基准一致、`kernel` 偏移 `0xac00`、无 `__symbols__`、`backlight` 无 phandle。

**本任务不产生提交**（无代码改动）。

---

### Task 3: 实体板端到端验证

**Files:**
- 无改动；纯验证

**Interfaces:**
- Consumes: Task 2 下载的 `/tmp/ci-ultra/output/image/update.img`
- Produces: 供 Task 4 回填 plan「验证证据」段的实测数值

- [ ] **Step 1: 让板子进入 Maskrom 并烧录**

按住 BOOT 键上电（或用 `adb reboot loader` 后按提示）使设备出现在下载列表，然后烧录：

```bash
cd /Users/yuangezhizao/Downloads/upgrade_tool_v2.25_for_mac
./upgrade_tool LD
./upgrade_tool UF /tmp/ci-ultra/output/image/update.img
```

期望：`LD` 列出 `Mode=Maskrom`；`UF` 末尾打印 `Upgrade firmware ok.`。

- [ ] **Step 2: 等待启动，采集出厂态（720×720）指标**

```bash
for i in $(seq 1 50); do sleep 3; adb devices 2>/dev/null | grep -q 'device$' && { echo "ADB ready"; break; }; done
adb shell "
echo -n '内核: '; uname -a
echo -n 'bl_power = '; cat /sys/class/backlight/backlight/bl_power
echo -n 'iomux 3 27: '; iomux 3 27
echo -n 'backlight phandle: '; od -An -tx1 /sys/firmware/devicetree/base/backlight/phandle 2>/dev/null || echo '(无该属性)'
"
```

期望：内核版本串为本次构建时间；**`backlight phandle` 打印 `(无该属性)`**；`bl_power = 0`；`iomux 3 27 = 2`。此时分辨率还是出厂的 720×720，480 屏未必有正常画面，但**背光应该已经亮起**——这本身就是修复生效的第一个信号。

- [ ] **Step 3: 切到 480×480 并重启**

出厂 `/etc/luckfox.cfg` 尚无 RGB 段，`rgb_switch` 会直接切到 480。

```bash
adb shell "luckfox-config rgb_switch 2>&1 | grep -E 'Switch|resolution'"
adb reboot; sleep 8
for i in $(seq 1 50); do sleep 3; adb devices 2>/dev/null | grep -q 'device$' && { echo "ADB ready"; break; }; done
adb shell "/oem/usr/bin/modetest -M rockchip 2>/dev/null | grep -E '^  #0' | head -1"
```

期望：打印 `***Switch the RGB screen resolution to 480 x 480.***`；重启后 `modetest` 报 `#0 480x480 59.94 … 16500`。若仍显示 720×720，再 `adb reboot` 一次——boot 分区 DTB 改写偶尔需要第二次重启才稳定（spec §10 Q6 已记录该现象）。

- [ ] **Step 4: 按 spec §8 判据逐项采集**

```bash
adb shell "
mount -t debugfs none /sys/kernel/debug 2>/dev/null
echo -n 'bl_power         = '; cat /sys/class/backlight/backlight/bl_power
echo -n 'brightness       = '; cat /sys/class/backlight/backlight/brightness
echo -n 'iomux 3 27       : '; iomux 3 27
echo -n 'backlight phandle: '; od -An -tx1 /sys/firmware/devicetree/base/backlight/phandle 2>/dev/null || echo '(无该属性)'
cat /sys/kernel/debug/pwm | tail -1
/oem/usr/bin/modetest -M rockchip 2>/dev/null | grep -E '^  #0' | head -1
"
```

期望全部命中：`bl_power = 0`、`brightness = 255`、`iomux 3 27 = 2`、`backlight phandle` 为 `(无该属性)`、pwm 行含 `requested enabled` 且 `duty: 100000 ns`、分辨率 `480x480 … 16500`。

- [ ] **Step 5: 人工确认屏幕**

请板子持有者目视确认：**背光亮起且 480×480 有画面**。

这一项不可省略也不可用命令替代——本次排查已充分证明「软件层全绿」与「屏幕真的亮」是两回事，`modetest` 成功不构成点亮的证据（spec §2.2）。若命令全部通过但屏幕仍黑，停止并回到 spec §4 重新分析，不要直接进入 Task 4。

**本任务不产生提交**（纯验证）。

---

### Task 4: 回填验证证据、提交文档并开 PR

**Files:**
- Modify: `docs/superpowers/plans/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604.md`（本文件的「验证证据」与「与计划的偏离及原因」两节）
- Create（入库）: 上述 plan 与已存在的 spec

**Interfaces:**
- Consumes: Task 2、Task 3 的实测数值
- Produces: PR

- [ ] **Step 1: 回填本文件末尾两节**

把 Task 2 Step 5 与 Task 3 Step 4 的**实测输出**（可复现命令 + 实际数值）填入「验证证据」；把任何与本计划不一致的做法及原因填入「与计划的偏离及原因」。只填这两类内容，不要写操作流水或评审过程。

- [ ] **Step 2: 确认工作区状态**

```bash
cd /Users/yuangezhizao/Documents/IDF/luckfox-pico
git status --short
```

期望：只有两份文档待提交（spec 为新增、plan 为新增）。若 `hostapd` / `hostapd_cli` / `librkwifibt.so` 被本地编译改写过，用 `git checkout -- <file>` 恢复。

- [ ] **Step 3: 提交两份文档**

```bash
git add docs/superpowers/specs/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604-design.md \
        docs/superpowers/plans/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604.md
git commit -m "$(cat <<'EOF'
docs(superpowers): 📝 Luckfox Pico Ultra RGB 屏点亮的 spec 与 plan

- 记录三份固件的全量对比，为「以 260604 而非 250607 作对齐基准」留下依据
- 沉淀被证伪的假设（双 DTB、model 字符串、route_rgb、FDT 溢出、U-Boot rgb-reset 等），避免日后重复调查
- 记录 strings 启发式统计模块数会数量级高估这一踩坑，文件级事实一律以 ext4 目录树解析为准
EOF
)"
```

- [ ] **Step 4: 推送并开 PR**

```bash
git push
gh pr create --base dev --title "fix(kernel): 🐛 关闭 CONFIG_DTC_SYMBOLS 修复 Ultra RGB 屏背光不亮" --body "$(cat <<'EOF'
## 背景

本仓 CI 产出的 Luckfox Pico Ultra（eMMC）固件刷入实体板后，官方 LP40-480480-ARK 480×480 RGB 屏完全不亮，而官方预编译固件在同一硬件上正常点亮。

## 根因

`luckfox_rv1106_linux_defconfig` 开启了 `CONFIG_DTC_SYMBOLS`，使 dtc 带 `-@` 编译，为所有带 label 的节点生成 phandle。`pwm_bl` 见到 `backlight` 节点有 phandle 就认为「另有驱动会在合适时机点亮背光」而返回 `FB_BLANK_POWERDOWN`，但 RGB panel 链路上并不存在那个驱动。结果 PWM 从未 enable，`pwm-rockchip` 也就不会切到 `active` 引脚状态，GPIO3-27 停在 GPIO 模式、背光电路无驱动波形——而 sysfs 里 `brightness` 仍显示 255，极具迷惑性。

## 改动

`luckfox_rv1106_linux_defconfig` 一行：`CONFIG_DTC_SYMBOLS=y` → `# CONFIG_DTC_SYMBOLS is not set`。

## 验证

- 离线用内核自带 dtc 重编：改动后产出的 DTB 与官方 260604 固件内的 DTB **逐字节相同**
- 实体板 A/B 对照：只换 boot 分区，`backlight` phandle 的有无与背光是否点亮一一对应
- CI 三个组合（Pico Max SD_CARD / SPI_NAND、Ultra EMMC）编译通过
- 刷机后按 spec §8 判据全部命中，屏幕人工确认点亮

## 影响面

该 defconfig 被 13 个 BoardConfig 共用，全板型 DTB 都会变小；其中只有 Ultra 与 86Panel 含 `backlight` 节点，其余板型不走该判定路径。720×720 屏与 86Panel 无实物，未验证。

详见 `docs/superpowers/specs/2026-08-23-luckfox-pico-ultra-emmc-rgb-align-260604-design.md`。
EOF
)"
```

---

## Self-Review（写完后自查记录）

- **spec 覆盖**：§5.1 方案 A → Task 1；§7 预期产物变化 → Task 2 Step 5；§8 构建级判据 → Task 2 Step 3，板级判据 → Task 3 Step 4/5；§6.4 影响半径（三组合都要编）→ Task 2 Step 3；§10 Q10 交付方式 → Task 4。§5.2 方案 B 按 Global Constraints 明确不实施。§8「已知未验证项」在 PR 正文中如实声明。
- **占位符**：无 TBD / TODO；每个需要命令的步骤都给了可直接执行的完整命令与期望输出。末尾两节标注为执行后回填，属结果记录区而非未完成的计划内容。
- **一致性**：Task 1 产出的两个基准值（`41740` / `60e69283…`）在 Task 2 Step 5 被原样引用；`backlight phandle` 的判定方式在 Task 1、2、3 中保持一致（离线看 DTS、板上看 `/sys/firmware/devicetree/base/backlight/phandle` 是否存在）。
- **任务边界**：Task 1 与 Task 2 之间可独立评审（前者是源码改动 + 秒级离线证明，后者是构建回归）；Task 3 依赖实体硬件、单独成任务；Task 4 只做文档与交付。仅 Task 1 与 Task 4 产生提交，符合「文档留最后一次提交」的约定。

## 验证证据

### CI 三组合编译与产物校验

```bash
gh run view 32616072092 --json status,conclusion,jobs \
  -q '"总体: \(.status) \(.conclusion)", (.jobs[] | "  \(.name): \(.conclusion)")'
```

```
总体: completed success
  🐳 构建 CI 镜像: success
  🛠️ Luckfox Pico Max · SD_CARD: success
  🛠️ Luckfox Pico Ultra W · EMMC: success
  🛠️ Luckfox Pico Max · SPI_NAND: success
```

run `32616072092` 于 `2026-08-23T03:43:40Z` 开始、`05:00:46Z` 结束，全程 77 分钟；产物 `SHA256SUMS` 经 `shasum -a 256 -c` 校验，11 个文件全部 OK。

按 Task 2 Step 5 的 Python 命令解析 `/tmp/ci-ultra/output/image/boot.img`：

```
boot.img 总体积 : 3793408 B
DTB 体积        : 41740 B            期望 41740        ✅
DTB SHA256      : 60e6928362602b44f6884e9e5f0b20996f23574db4d29bfed378809670e15cfa
                  与官方 260604 固件内 DTB 逐字节相同  ✅
kernel 偏移     : 0xac00             期望 0xac00       ✅
__symbols__     : 无 ✅
backlight phandle: 无 ✅
```

### 实体板烧录与出厂态

```bash
adb reboot loader && sleep 8
cd /Users/yuangezhizao/Downloads/upgrade_tool_v2.25_for_mac
./upgrade_tool LD          # → DevNo=1 Vid=0x2207,Pid=0x110c Mode=Maskrom
./upgrade_tool UF /tmp/ci-ultra/output/image/update.img
```

```
Support Type:1106	FW Ver:0.0.00	FW Time:2026-08-23 13:00:03
Loader ver:1.01	Loader Time:2026-08-23 11:46:46
...
Download Firmware Success
Upgrade firmware ok.
```

刷完首次启动、未做干预且分辨率保持出厂 `720×720` 时：

```
内核             : 5.10.160 #1 Sun Aug 23 11:47:09 CST 2026
fwver            : uboot-08/23/2026
model            : Luckfox Pico Ultra
backlight phandle: (无该属性)
bl_power         = 0
brightness       = 255
iomux 3 27       : mux get (GPIO3-27) = 2
pwm              : pwm-0 (backlight): requested enabled period: 100000 ns duty: 100000 ns
分辨率           : #0 720x720 48.87 ... 30000
```

切换分辨率之前，背光相关指标均已达标；板子持有者在切换至 480×480 后现场目视确认背光亮起且正常出画面，内核与 U-Boot 版本串确认运行的是完整自编译固件。

### 480×480 切换与板级判据

```bash
adb shell "luckfox-config rgb_switch"   # → ***Switch the RGB screen resolution to 480 x 480.***
adb reboot
```

```
bl_power          = 0                                                    ✅
brightness        = 255                                                  ✅
iomux 3 27        : mux get (GPIO3-27) = 2                               ✅
backlight phandle : (无该属性)                                            ✅
pwm               : pwm-0 (backlight): requested enabled … duty: 100000 ns  ✅
DRM 连接器        : connected / enabled                                   ✅
分辨率            : #0 480x480 59.94 480 530 534 544 480 488 498 506 16500 ✅
boot 分区内 fdt   : 41744 B（出厂 41740 + rgb_switch overlay 增 4 字节）    ✅
kernel 偏移       : 0xac00                                                ✅
```

板子持有者现场目视确认背光亮起，且 480×480 正常出画面。

## 与计划的偏离及原因

1. `boot.img` 实测为 `3,793,408 B`，计划预推为 `3,792,896 B`，相差 `512 B`。预推使用上一版构建的内核体积 `3,667,920 B`，本次内核略大并跨入下一个 `512 B` 块；实测值与官方 260604 的 `boot.img` 完全相等。
2. `rgb_switch` 仅重启一次即切换到 `480×480`；计划为 boot 分区 DTB 改写偶尔需要第二次重启预留的处理未触发。
3. 本机磁盘空间不足使 artifact 下载两次失败：`228 GB` 系统盘仅余 `166 MB`。清理 `913 MB` 重复固件副本及 `908 MB` 已被本次 CI 产物替代的旧自编译产物目录后下载完成；重跑本计划需预留约 `1.5 GB` 空闲空间，以容纳 artifact zip 暂存与解压的两份空间。
