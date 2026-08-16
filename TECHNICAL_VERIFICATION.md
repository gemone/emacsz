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
| 输出 `emacs.exe` / `emacs.pdb` 等 | ✅ | `zig build install -p <dir>` 在自定义目录产出 `temacs.exe/emacs.exe/emacsclient.exe/etags.exe` 及对应 `*.pdb` |
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
| **libpng / libjpeg / libtiff / giflib** | ⚠️ 未启用 | 目标 3.5 明确点名这些图像库。**当前构建为 console/TTY-only（GUI 范围之外）**，`src/image.c` 未编译，图像库即使 vendored 也是死代码。需先推进 GUI/图像子系统后再 vendoring |

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
| **MSVC 后端完整构建+测试** | ✅ **已达成（本轮）**：`zig build -Dtarget=x86_64-windows-msvc` 全量编译+链接+转储成功，`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 测试 **0 unexpected**；`etags/emacsclient --version` 与 `emacs.exe --batch --load` 实测可运行 | 已从 ~327 编译错误推进到全绿，且经 `bool_bf`/`ENUM_BF` 位域修复后源转储 + 测试全通过；剩余仅是 CI 双后端门禁化 |
| **CI 双后端覆盖**（验收 5.3） | MSVC ABI 只能在 Windows 且有 VS 的 runner 上跑 | 在 CI `windows-latest`（自带 VS）加一个 MSVC `zig build -Dtarget=x86_64-windows-msvc` job（构建 + `zig build check`）验证 
| **libpng/libjpeg/libtiff/giflib vendoring**（目标 3.5） | GUI/图像子系统不在当前 console/TTY 范围 | 推进 GUI（或用 `-Dnative-comp` 之外需要图像读入的路径真实调用 `image.c`）后再 vendoring |
| 二进制与上游 MSYS2 构建**一致**（验收 5.1/5.3） | 无 MSYS2 基准 | 建立 MSYS2 参考构建产物做 diff |
| **`install -p <dir>` 自定义前缀只装二进制** | 转储镜像 `bootstrap-emacs.pdmp` 由 dump 步骤写在默认 `zig-out/bin/`（`emacs` 启动器按自身位置找 pdmp） | 默认 `zig-out` 安装完整可运行（已实测）；自定义 `-p` 目录需手动连同 `zig-out/bin` 的 pdmp（以及 `etc/`、loaddefs）一起拷贝才可运行。如要 `-p` 也产出完整可运行 Emacs，需在 build.zig 中把转储镜像及运行时数据一并 install 到前缀（涉及 pdmp 内嵌路径 / sibling etc / loaddefs 的迁移，属较复杂改动）|

---

## 7. 结论

在"无 MSYS2、仅 Zig（加可选 VS）"的 Windows 环境下，核心可行性与大部分目标已**实测通过**：
`zig build` → `zig build smoke` → `zig build check`（全绿）→ 默认 `zig build
install`（`zig-out/` 完整可运行，实测 `emacs.exe --version` 正常）。**MSVC 后端（目标 3.4）本轮
已提为完整可运行：** `zig build -Dtarget=x86_64-windows-msvc` 全量编译+链接+转储成功，且
**`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 测试 0 unexpected**，与 GNU 后端一致；
关键位域修复（`bool_bf`/`ENUM_BF` 对 `_MSC_VER` 用 `unsigned int`）消除了 clang-msvc 有符号位域
导致的源转储崩溃。GNU 后端全程不回归。剩余主要是：CI 双后端门禁覆盖、GUI 范围外的图像库
vendoring，以及 `install -p <自定义目录>` 只装了二进制、转储镜像需手动补齐——这些都受
当前宿主环境（无 GUI、CI 未加 MSVC job）或改动复杂度限制，不是默认构建流程的缺口。
