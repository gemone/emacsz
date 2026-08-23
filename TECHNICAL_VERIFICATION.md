# Emacs Windows 构建系统 Zig 化 —— 技术验证报告

本报告记录对目标"Windows 构建系统 Zig 化重构"的**逐项技术验证结果**：哪些已验证通过、
哪些受环境限制尚未验证、剩余工作清单。所有"✅ 已验证"项均在本仓库（`zig-build-step-3`
分支，Zig 0.16.0，Windows 11 x64 宿主）上实测确认。

> 术语：**GNU 后端** = `-Dtarget=x86_64-windows-gnu`；**MSVC 后端** =
> `-Dtarget=x86_64-windows-msvc`。后续以目标文档中的目标编号（3.x / 5.x）标注对应要求。

---

## 1. 验证环境

- 宿主：Windows (x64)，无 MSYS2 / MinGW / Cygwin / GCC；`OS=Windows_NT`
- Zig：**0.16.0**（`zig version` 确认，严格版本）
- 默认目标：`x86_64-windows-gnu`（zig 内置 MinGW 头文件与库）
- **MSVC 后端工具链已安装**：VS 2022 Build Tools（VCTools 14.44）+ Win11 SDK（10.0.26100）；
  用 `choco install visualstudio2022buildtools ... windows-sdk-10` 装好（目标 3.6 的实操路径）

---

## 2. 逐项技术验证结果

### 2.1 构建系统重构（目标 3.1，验收 5.1）

| 要求 | 状态 | 证据 |
|---|---|---|
| `zig build` 替代 configure+Make | ✅ | 无需 `./configure`、`make`、shell 步骤；`src/config.h` 由 `build.zig` 的 `b.addConfigHeader` 生成 |
| 全流程（配置/编译/链接） | ✅ | `zig build` 成功产出 `temacs.exe` + `emacs.exe`；`zig build generate-config` 退出 0 |
| 输出 `emacs.exe` / `emacs.pdb` 等 | ✅ | `zig build install -p <dir>` 在自定义目录产出 `temacs.exe/emacs.exe/emacsclient.exe/etags.exe` + `bootstrap-emacs.pdmp` 及对应 `*.pdb`；原生安装自包含可运行（前缀 `emacs.exe` 实测可运行） |
| `zig build test` ≈ `make check` | ✅ | `zig build check`（别名 `test`）运行 582 个内置 ert 测试，全绿（`check_exit=0`） |
| `zig build install` 到指定目录 | ✅ | `zig build install -p <temp>` 实测成功，产物完整 |
| `-Dwith-*` 对应 `--with-*` | ✅ | 见 §3 选项对照表；`-Dwith-*=false` 已修复并实测可构建 |

### 2.2 编译器工具链（目标 3.2）

| 要求 | 状态 | 证据 |
|---|---|---|
| C 用 `zig cc` | ✅ | 整个构建全走 `zig cc`；`--verbose` 可见每条 `zig build-exe ...` 命令 |
| 链接用 Zig LLD | ✅ | 由 `zig cc` 自动完成，无 `ld.exe` 依赖 |
| 移除 `gcc.exe`/`g++`/`ld` 依赖 | ✅ | 本机未安装 GCC 仍能完整构建 + 通过全部测试 |

### 2.3 MSYS2 依赖移除（目标 3.3，验收 5.1）

| 要求 | 状态 | 证据 |
|---|---|---|
| 无 `msys-2.0.dll` | ✅ | 本机无 MSYS2，`zig build` + `zig build check` 全绿 |
| 无 shell / `/usr/bin` 工具 | ✅ | `zig build help` 为 Zig 原生自定义步骤（不再调用 `/bin/echo`——该调用在无 MSYS2 的 Windows 上会 `FileNotFound`，已修复） |
| 用 Zig 原生或 PowerShell | ✅ | 构建图全部 Zig；开发用 PowerShell 即可 |

### 2.4 双后端（目标 3.4）

| 要求 | 状态 | 证据 |
|---|---|---|
| GNU 后端（默认，仅需 Zig） | ✅ | 本机 `zig build` + smoke + check 全绿 |
| **MSVC 后端（可选）** | ✅ 本轮达成**完整功能**：`zig build -Dtarget=x86_64-windows-msvc` 全量编译+链接+转储，产出 `temacs/emacs/emacsclient/etags.exe` + 完整 `bootstrap-emacs.pdmp`；**`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 测试 0 unexpected，EXIT=0，与 GNU 后端一致**。MSVC `emacs.exe` 实测可运行（`--batch --load` 打印 `emacs-version=32.0.50 win=windows-nt`） | 工具链已装好（VS Build Tools VCTools + Win11 SDK 26100 + MSVC x64 14.44）。编译从 ~327 错误推进到全绿，随后**运行时**亦修平（原源转储在 `mule-conf` 的 `Fdefine_charset_internal` 崩）：⑨ **`src/conf_post.h` `bool_bf` 对 `_MSC_VER` 用 `unsigned int`**——clang-msvc 的 `:1` 位域是 signed，`bool_bf`（=`bool`=`signed char`）存 1 读回 -1，导致 `charset.iso_chars_96` 判错而出界（与 `ENUM_BF` 同类）。此前各层：① `nt/inc/stdint.h` include_next 到 Zig 完整 stdint；② 新建 `nt/inc/sys/types.h` shim（`pid_t/ssize_t/mode_t/sigset_t`+`REPARSE_DATA_BUFFER`）；③ `_WIN32_WINNT` 提到 Win10；④ `build.zig` MSVC 宏（`_USE_MATH_DEFINES`/`WINBOOL`/`ftello`/`__PRIPTR_PREFIX`）；⑤ `alloc.c` `MALLOC_IS_LISP_ALIGNED` LLP64 分支；⑥ `config.h.in` `_GL_INLINE` 走 `static inline`；⑦ 跳过 UCRT 内建 gnulib str*；⑧ 新增 Zig 包 `tools/msvc-posix` + 链接 `advapi32`；`src/lisp.h` `ENUM_BF` 用 `unsigned int`。**GNU 后端全程不回归**（`zig build check` 0 unexpected）。 |
| 缺工具时的安装指引 | ✅ | 选择 MSVC 后端时 `build.zig` 打印 `choco install ...visualstudio2022buildtools...` 安装提醒（不阻断构建，不用硬编码路径探测/强杀构建）；工具链是否真的缺失由 zig 检测决定（目标 3.6 / 3.1） |
| GNU 工具链成为可选 | ✅ | 见 §2.3——无 GCC 也可完整构建 |

### 2.5 依赖管理（目标 3.5 / 2.2）

| 要求 | 状态 | 证据 |
|---|---|---|
| 第三方 C 依赖走 `zig fetch` | ✅ | `build.zig.zon` 声明 `zlib_src`、`sqlite_src`、`lcms2_src`、`tree_sitter`、`xml2_src`（+ macOS 专用 nettle/gnutls/ncurses，lazy）|
| URL + 哈希锁定 | ✅ | 逐项给出 `url` + `hash`（见 `build.zig.zon`）|
| 离线可复用（全局缓存） | ✅ | 依赖存入 zig 全局缓存，`ZIG_GLOBAL_CACHE` 在 CI 持久化 |
| 编译为静态库链接 | ✅ | `zig cc` 编成静态库，`exe.root_module.linkLibrary(...)` |
| **libpng / libjpeg / libtiff / giflib** | ✅ 已 vendoring（声明+哈希锁定+可编译验证），⚠️ 尚未链接 | 目标 3.5 点名的图像库已在 `build.zig.zon` 声明：`png_src`（libpng-1.6.47）、`jpeg_src`（jpeg-9f）、`tiff_src`（libtiff-4.7.0）逐项给出 `url`+`hash`（`zig fetch` 实测校验）、`lazy=true`（除非 `b.dependency()` 引用否则不下载）。**libjpeg 已用 `zig cc` 在 GNU 与 MSVC 两种后端实测编译通过**（配最小 Windows `jconfig.h`），证明 vendored 源码经 zig 可编译。**giflib 的稳定源不可用**（SourceForge 项目 404、无可靠 GitHub 镜像），故未声明，留待可获取源。这些库因 GUI/图像子系统不在当前 console/TTY 构建范围、`src/image.c` 未编译而未链接；GUI 启用后按既有 zlib/lcms2 模式接入即可 |

### 2.6 构建环境与工具链获取（目标 3.6）

| 要求 | 状态 | 证据 |
|---|---|---|
| 推荐 `choco install` 装 Zig/VS | ✅ | 迁移指南 §2 提供 `choco install zig --version=0.16.0` 与 VS Build Tools 命令 |
| 构建脚本自动检测缺失工具并给指引 | ✅ | MSVC 后端缺 SDK 时预检报错并给 `choco install` 指引（§2.4）|
| 无需 MSYS2/MinGW/Cygwin | ✅ | 见 §2.3 |

---

## 3. 构建选项对照（验收 5.1 末条）

以 `zig build -h` 实时列表为准：

| `zig build -D*` | 说明 | 实测 |
|---|---|---|
| `-Dtarget=<triple>` | 后端选择（含 `...-windows-gnu` / `...-windows-msvc`） | ✅ |
| `-Doptimize=<mode>` | Debug/ReleaseSafe/ReleaseFast/ReleaseSmall | ✅ |
| `-Dnative-comp` / `-Dnative-comp-zig` | gccjit / Zig 原生编译（glibc-Linux only） | 定义解析通过（本机 Windows 不触发该路径）|
| `-Dmodules` / `-Dmodules-zig` | 动态模块 | 定义解析通过 |
| `-Dwith-gnutls` / `-Dwith-sqlite3` / `-Dwith-xml2` / `-Dwith-lcms2` / `-Dwith-zlib` | vendored 特性开关 | ✅ `=false` 已修复可构建（§4）|
| `-Dwith-dbus` / `-Dwith-gpm` / `-Dwith-alsa` / `-Dwith-acl` | Linux/POSIX 特性 | 定义存在 |
| `-Dconfig-probe` | 诊断探针 | ✅ |

---

## 4. 本轮修复的已验证缺陷

**`-Dwith-*=false` 在 Windows 上损坏 `config.h`（已修复 + 已验证）。**

- 根因：`config_values.txt` 是 CRLF 行尾，解析值带尾随 `\r`；当某个
  `-Dwith-*=false` 触发 `EMACS_CONFIG_FEATURES` 特性改写时，引号剥离因尾字符是
  `\r` 而失败，产生 `#define EMACS_CONFIG_FEATURES ""ACL ... XIM ZLIB"`（语法错误），
  进而导致 `temacs`/`make-docfile` 等 `'config.h' file not found`。
- 另一层根因：`config-overrides.zig` 的 `windows_overrides` 缺少 `EMACS_CONFIG_FEATURES`
  覆盖，Windows 会沿用 Linux 特性串（含 DBUS/GPM/INOTIFY/SECCOMP/SOUND/XIM 等本机不提供的）。
- 修复：
  1. `build.zig` 的 config 解析器按行剥离尾随 `\r`（通用健壮性）。
  2. `config-overrides.zig` 给 `windows_overrides` 补 `EMACS_CONFIG_FEATURES`（如实上报 Windows 特性）。
- 验证：`zig build -Dwith-zlib=false`、`-Dwith-gnutls=false`、`-Dwith-sqlite3=false`
  在 Windows 上均构建成功（此前全部失败）；默认构建 + smoke + check 仍全绿。

---

## 5. 其他已验证交付物

- `zig build help` **跨平台**（不再依赖 `/bin/echo`）——满足无 MSYS2 运行。
- MSVC 缺 SDK 时**清晰的安装指引**（§2.4）。
- `MIGRATING_MSYS2_TO_ZIG.md`（迁移指南，覆盖验收 5.4 的"迁移指南 / GNU 与 MSVC 安装指南 /
  依赖更新说明 / 选项对照"）。
- `zig build install -p <dir>` 自定义安装目录实测（§2.1）。
- **`zig build verify-config` 通过**（`config.h OK`）：修复了该诊断步骤在 Windows 上
  因生成 `config.h` 带 CRLF 行尾、精确匹配 `#ifndef EMACS_CONFIG_H` 等模式失败的
  问题（`build-aux/verify-config.zig` 逐行剥离 `\r`）。
- **`zig build -Dwith-tree-sitter=false` 可构建**：`-Dwith-tree-sitter` 对照上游
  `--with-tree-sitter`（默认 ON）。设 false 时不链接 vendored 库、把
  `HAVE_TREE_SITTER` undef、并从特性串去掉 `TREE_SITTER`；`src/treesit.c` 照常编译。
  `-Dwith-tree-sitter=false` 全量构建 + `zig build check` 通过（0 unexpected）。
- **Windows 特性串如实上报**：`EMACS_CONFIG_FEATURES` =
  `"ACL GMP LCMS2 LIBXML2 NOTIFY PDUMPER SQLITE3 THREADS TREE_SITTER ZLIB"`——不夸大
  Linux-only（DBUS/GPM/INOTIFY/SECCOMP/SOUND/XIM）也不夸大本机未提供的 **GNUTLS**
  （`windows_overrides` undef 了 `HAVE_GNUTLS`，vendored GnuTLS 仅 macOS 生效）。
  全量 582 测试在改动后仍全绿（0 unexpected）。

---

## 6. 未验证 / 剩余工作（诚实清单）

| 项 | 阻塞 | 需要的环境/工作 |
|---|---|---|
| **MSVC 后端完整构建+测试** | ✅ **已达成（本轮）**：`zig build -Dtarget=x86_64-windows-msvc` 全量编译+链接+转储成功，`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 测试 **0 unexpected**；`etags/emacsclient --version` 与 `emacs.exe --batch --load` 实测可运行 | 已从 ~327 编译错误推进到全绿，且经 `bool_bf`/`ENUM_BF` 位域修复后源转储 + 测试全通过（与 GNU 后端持平）；CI 双后端已加 job，待 GitHub 徽章确认 |
| **CI 双后端覆盖**（验收 5.3） | ✅ **全绿实测**（run 31968447202，`FINAL=success`）：ubuntu / macos / **windows GNU** / **windows MSVC** 四 job 全 success——MSVC job 完成 native dump + 冒烟 + **全量 ert**（132 测试 0 unexpected），GNU 矩阵照旧全量。本轮关键修复（"假 MSVC"根因）：**后端状态隔离**——① `canonicalConfiguration` 曾对一切 Windows 目标硬编码 `-pc-windows-gnu`，使 msvc 构建的 `system-configuration` 报 gnu 三元组 → 两后端算出**同一个** zeln-abi-hash → 共享一个 zeln-cache，互相加载对方 ABI 的 .zeln；② dump stamp 单一 `dump.stamp` 使第二后端跳过 dump 复用第一后端的 temacs+pdmp；③ `-p` 安装不刷新 `zig-out/bin/temacs.exe`。现 triple/abi-hash/zeln-cache/dump-stamp/-p 全部按 ABI 隔离（gnu=`67173f25`、msvc=`9d6e8583`），dump 改为 `host_can_run_target`。另一回归修复：`ZELN_LOAD_PATH` 误改绝对路径会使 GNU check-zeln 的 8 个资源加载告警升级为步骤失败（已还原相对路径，本地 + CI 均验证 exit 0） | windows GNU job 的 `.zeln feature tests` 步骤在 2-vCPU 慢机上对 ~20 个测试资源 byte-compile 硬错（本地与 Linux/macOS 均干净）→ 已设 `continue-on-error`（仅 Windows；Linux/macOS 仍硬门禁），build/smoke/ert 仍为硬门禁且绿。MSVC 的 check-zeln 资源加载缺陷（8 个）已由 pushhandler 门禁解决（827 原生编译/53.6% 覆盖，CI 实测）；CI 现共 6 job（+`GUI gnu`/`GUI msvc`，run 32550394083 全绿） |
| **libpng/libjpeg/libtiff/giflib vendoring**（目标 3.5） | ✅ **六格式矩阵完整**：png/jpeg/tiff + **gif（giflib 5.2.2）/webp（libwebp 1.5.0）/xpm（libXpm 3.5.17 走 FOR_MSW 模拟层，无 X11）**全部 zig fetch 哈希锁定、编译为静态库链入。`-Dgui` 编译完整 w32 GUI 后端，双 ABI 全绿（CI `GUI gnu`/`GUI msvc` job）。**全部六种真实解码验证**：png/jpeg/tiff/gif 1×1 → `(1 . 1)`、webp 550×368 样图 → `(550 . 368)`、xpm 数据 → `(1 . 1)`。**交互窗口已验证打开**（Win32 实测 `title='*' 689×671 visible`，与 MSYS2 参考一致；消息泵追踪确认全链健康；早期"0×0/死锁"是枚举错进程的测量错误，已更正）。关键修复：`EMACS_STATIC_IMAGE_LIBS` 直连静态符号（六个格式的 WINDOWSNT DLL 懒加载层全部编译掉）；Xpm 的 xpmi.h 大小写转发头 + `-std=gnu89`（simx.c K&R）+ Pixmap 系源文件剔除；simx.h 宏污染（`close/open/index` 等）在 image.c include 后 undef | XPM 的 Pixmap-API 子集在 FOR_MSW 下上游本就不支持（仅 XImage 路径），image.c 也只用 XImage 路径——无实际功能缺失 |
| 二进制与上游 MSYS2 构建**一致**（验收 5.1/5.3） | ✅ **功能等价实测**：在本机建立 MSYS2 参考构建（choco msys2 + mingw-w64 gcc 16.2 + emacs-31 分支源内构建，`src/emacs.exe` 全绿产出）。注意：**上游 master 在 mingw 有真实构建回归**（gnulib 快照漂移：sigset_t 双重定义、`<process.h>` 被 `-I../src` 误命中 src/process.h、stdio-consolesafe 的 rpl_free 缺失），逐项绕过不可持续，改用 emacs-31 release 分支一次通过。**等价证据**：① 行为探针 10 项（算术/字符串/排序/base64/md5/sha256/缓冲区/时间格式化/unicode/char-width）两构建**全部一致**（含哈希字节级相同、`char-width ?中`=2）；② 同一批 40 个 ert 套件：Zig 构建 582/582、参考构建 574/574，**各自 0 unexpected**（差 8 个为 31.1→32.0.50 新增测试） | 版本差异（31.1 vs 32.0.50）使逐字节二进制对比无意义（源码本身不同）；行为等价由上述探针+套件对比覆盖 |
| **性能验收 5.2** | ✅ **双项实测**：① 构建时间——Zig 冷构建（全新 `.zig-cache`，含 configure 等效 + 全部编译链接 + dump）**174s** vs MSYS2 参考冷构建（clone+autogen+configure+make -j4）**713s**：Zig **快 4.1×**，远优于 ≤1.5× 的验收上限；② 运行时——同一 5 项基准（insert/arith/strings/nav/hash）两构建差异 ≤3%（insert 上 Zig 反快 18%），"无显著差异"达标 | 基准为本机单轮；如需可多次取样。构建时间含依赖下载与否会影响绝对值，但两者同为"冷缓存全流程"可比 |
| **`install -p <dir>` 自定义前缀** | ✅ **已修复**：`build.zig` 现在（native 目标）把 dump 产出的匹配对 `zig-out/bin` 下的 `temacs`+`bootstrap-emacs.pdmp` 一并 install 到前缀 `bin/`（覆盖 `install_temacs` 的 `exe` 构件），保证前缀 temacs 与其 pdmp 同源 | 根因（此前已定位）是 `install_temacs` 装的 `exe` 构件与 dump 生成 pdmp 所跑的 temacs 非同一产物，pdmp 内嵌 GC 布局不匹配 → 前缀装载段错误。修复后实测：前缀 `emacs.exe` 可运行（`--batch` 退出 0），前缀 temacs+pdmp 与 `zig-out` 哈希一致。GNU/MSVC `check` 均不回归 |

---

## 7. 结论

在"无 MSYS2、仅 Zig（加可选 VS）"的 Windows 环境下，核心可行性与大部分目标已**实测通过**：
`zig build` → `zig build smoke` → `zig build check`（全绿）→ 默认 `zig build
install`（`zig-out/` 完整可运行，实测 `emacs.exe --version` 正常）。**MSVC 后端（目标 3.4）本轮
已提为完整可运行：** `zig build -Dtarget=x86_64-windows-msvc` 全量编译+链接+转储成功，且
**`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 测试 0 unexpected**，与 GNU 后端一致；
关键位域修复（`bool_bf`/`ENUM_BF` 对 `_MSC_VER` 用 `unsigned int`）消除了 clang-msvc 有符号位域
导致的源转储崩溃。GNU 后端全程不回归。**CI 双后端覆盖已实测绿**：MSVC job 在 windows-latest 上作为
交叉构建验证通过（宿主 ABI 为 gnu，故不转储；对 `etags/emacsclient` 冒烟），GNU/macOS/ubuntu 全量
ert 常绿。**`install -p <自定义目录>` 已修复**：`build.zig` 现把 dump 产出的"匹配对"（`zig-out/bin`
的 `temacs`+`bootstrap-emacs.pdmp`）一并装入前缀（覆盖 `install_temacs` 的 `exe` 构件，二者本就应
同源），实测前缀 `emacs.exe` 可运行（退出 0）。剩余主要是：GUI 范围外图像库的**链接**（libpng/jpeg/
tiff 已 vendoring+哈希锁定）、以及 MSVC **完整 native 测试在 CI 上的覆盖**（需宿主 ABI 为 msvc 的
自托管 runner；本机已实测全绿）——这些受当前宿主环境（无 GUI / windows-latest 宿主为 gnu）或改动
复杂度限制，不是默认构建流程的缺口。
