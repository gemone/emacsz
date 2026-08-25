# Emacs Zig Native Build System

这是GNU Emacs的Zig原生构建系统，作为Phase 2的一部分，提供TUI-only构建。

> **从 MSYS2/MinGW 迁移到 Zig 构建？** 见 [MIGRATING_MSYS2_TO_ZIG.md](MIGRATING_MSYS2_TO_ZIG.md)
> （分步迁移指南、构建选项对照、Windows GNU/MSVC 后端安装指南、`build.zig.zon`
> 依赖管理说明）。
>
> **技术验证报告**：见 [TECHNICAL_VERIFICATION.md](TECHNICAL_VERIFICATION.md)
> （逐项对照目标文档的验证状态、已验证与未验证清单）。

## 快速开始

```bash
# zig build 是唯一入口：首次构建会自动运行 ./configure 生成 src/config.h，
# 然后编译链接 temacs。无需手动 configure，也无需 make。
zig build

# 生成 bootstrap 数据（一次）
zig build generate-charsets
zig build generate-unidata
zig build generate-charprop    # uni-*.el / charprop / idna-mapping ...
zig build generate-cedet-grammars

# 转储可运行的 bootstrap emacs（从源码）
zig build dump

# 字节编译全部 lisp 并二次转储（最终镜像，check/check-all 使用）
zig build compile-lisp
zig build dump-compiled

# 生成 autoloads（dump 会清掉它们；check 步骤会自动重新生成）
zig build generate-loaddefs

# 运行
./zig-out/bin/emacs --batch --eval '(progn (message "Hello, World!") (kill-emacs))'

# 测试
zig build check        # 582 个内置 ert 测试（40 个套件）
zig build check-all    # 全部 484 个套件（上游 make check 的发现规则）
```

`zig build smoke` 会按顺序自动执行 dump → generate-loaddefs →
compile-lisp → dump-compiled → 最终 loaddefs 生成 → smoke，因此
一条命令即可得到最终可用的（字节编译的）转储镜像。

## 构建选项

- `-Doptimize=Debug` - 调试模式（默认）
- `-Dtarget=<triple>` - 选择目标后端（arch+OS+ABI，Zig 标准机制）：
  - 默认后端 = 本机目标；Windows 本机默认即 `x86_64-windows-gnu`（GNU/MinGW，
    用 Zig 内置的 MinGW 头文件与库）。
  - **MSVC 后端**（目标 3.4）：`-Dtarget=x86_64-windows-msvc`，调用
    Visual Studio / Windows SDK 工具链（仅 Windows 宿主可用，且需要已安装
    VS Build Tools / Windows SDK；缺 SDK 时 `zig build` 会打印 `choco install`
    安装提醒，工具链是否真的缺失由 zig 检测决定）。
  不需要额外的 ABI 专用开关——`-Dtarget` 已完整编码 arch+OS+ABI。
- `-Dnative-comp=[bool]` - gccjit 原生编译路径（.eln，`HAVE_NATIVE_COMP`，
  `src/comp.c`）。默认 OFF。仅在本机 glibc-Linux 上生效（libgccjit 是宿主
  库，不能交叉编译）；非本机/musl/windows/macos 自动关闭。开启需要系统
  安装 libgccjit（链接 `-lgccjit`），且 `libgccjit.h` 的 include 路径在构建
  时通过 `cc -print-file-name=include` 推导。
- `-Dnative-comp-zig=[bool]` - Zig/LLVM 原生编译路径（.zeln，
  `HAVE_NATIVE_COMP_ZIG`，`src/compz.c`）。默认 OFF。仅在本机 glibc-Linux 上
  生效。与 `-Dnative-comp` **相互独立**，两者可同时开启（M2.5 共存）。
- `-Dwith-tree-sitter=[bool]` - 是否启用 tree-sitter（`HAVE_TREE_SITTER`，
  vendored via `zig fetch`），对照上游 `--with-tree-sitter`。默认 ON；设
  `false` 时不链接 vendored 库并把 `HAVE_TREE_SITTER` undef（`treesit-available-p`
  报不可用，`src/treesit.c` 照常编译）。
- `-Dgui=[bool]` - 编译完整 w32 GUI 后端（`HAVE_NTGUI`，仅 Windows）。
  默认 OFF（console/TTY 构建）。详见上文"GUI 构建与图像格式"。
- `-Dwith-png / -Dwith-jpeg / -Dwith-tiff / -Dwith-gif / -Dwith-webp /
  -Dwith-xpm=[bool]` - 六种图像格式的 vendored 解码器（对照上游
  `--with-png` 等），Windows 目标默认 ON（与 `-Dgui` 一起构成完整 GUI
Emacs）；其他平台默认 OFF。源码经 `zig fetch` 下载（哈希锁定）、
  编译为静态库链入 temacs——不需要系统库也不需要运行期 DLL。
- 其余 `-Dwith-*`（gnutls/dbus/gpm/alsa/acl/sqlite3/xml2/lcms2/zlib）与
  上游同名选项一一对应；Windows 目标会自动关闭不适用的（DBUS/GPM/ALSA
  等见 `config-overrides.zig`）。

### 原生编译共存与优先级（M2.5）

两个原生编译路径物理隔离：`comp.c` vs `compz.c`、`.eln-cache` vs
`.zeln-cache`、不同的 ABI 哈希与版本目录、不同的 el→native 哈希表。两者
**永不冲突**。当两者同时开启、且某个 `.elc` 同时存在匹配的 `.eln` 和
`.zeln` 时，Lisp 变量 `native-comp-z-prefer` 决定加载哪一个：

- `nil`（默认）= 优先 `.eln`（gccjit）；`.zeln` 仅在没有 `.eln` 时作为回退。
  保守默认——同时开启时 `zig build check` 582/582 全程走 gccjit `.eln` 路径，
  与 gate #2（`.zeln` 执行崩溃）解耦。
- `t` = 优先 `.zeln`（opt-in；显式测试 `.zeln` 路径，即 gate #2 领域）。

实现：`src/lread.c` 的 `openp` 在两个调用点（普通路径 + newest/save_fd 路径）
依据 `native_comp_z_prefer` 重排 `maybe_swap_for_eln` / `maybe_swap_for_zeln`
的顺序——每个 swap 都以文件名以 `.elc` 结尾为前置条件，命中后会把它改写成
原生构件路径，所以**第一个**找到新鲜原生文件的 swap 胜出（第二个 swap 看到
非 `.elc` 名便提前返回）；没找到的 swap 不动文件名，让另一个执行（回退）。
因此优先的构件**先执行**并胜出。仅在 `HAVE_NATIVE_COMP_ZIG` 下生效；关掉该
宏时 `openp` 与原先逐字节一致（默认 `nil` 分支正是 HEAD 顺序：eln 先、zeln 后）。

注意：早期的 `ReleaseFast` 在加载转储时崩溃的问题（pdumper 单-delta
重定位缺陷）已修复——如今 CI 与本机验证全部使用
`-Doptimize=ReleaseFast`（构建、dump、582 测试、GUI、zeln 门禁均绿）。

## Windows 构建（无 MSYS2）

Windows 后端（`x86_64-windows-gnu`，默认）只依赖一个 **Zig 0.16.0**，
无需 MSYS2 / MinGW / Cygwin；所有第三方 C 依赖（zlib、libxml2、sqlite3、
lcms2、tree-sitter，以及可选的 libpng/libjpeg/libtiff/giflib/libwebp/
libXpm）都在 `build.zig.zon` 里声明并通过 `zig fetch` 自动下载、
编译为静态库链接。这是纯本机构建——在当前 Windows 主机上运行 `zig build`
即用 GNU 后端构建出可运行的 `temacs.exe` + `emacs.exe`：

```bash
# GNU/MinGW 后端（默认）：Windows 目标默认即 x86_64-windows-gnu。
# 默认产出完整 GUI Emacs（w32 显示后端 + 六种 vendored 图像格式）。
# 无参数即可：
zig build

# 或显式写出（目标 3.4 双后端选择）
zig build -Dtarget=x86_64-windows-gnu

# 退回纯 console/TTY 构建（无 GUI、无图像库）：
zig build -Dgui=false -Dwith-png=false -Dwith-jpeg=false -Dwith-tiff=false \
          -Dwith-gif=false -Dwith-webp=false -Dwith-xpm=false

# MSVC 后端（可选，目标 3.4）：同样默认 GUI + 六图像格式。
# 需要本机已安装 Visual Studio Build Tools / Windows SDK。
zig build -Dtarget=x86_64-windows-msvc

# 验证产物
zig-out\bin\emacs.exe --version
```

Windows 目标的 `-Dgui` 与六个 `-Dwith-*` 图像开关默认均为 **on**
（与 MSYS2 参考构建的默认行为一致：GUI + 完整图像支持）；Linux /
macOS 无 w32 GUI，保持 console 默认。可用上述 `-Dgui=false -Dwith-*=false`
显式退回 console-only 构建。

### GUI 构建与图像格式（可选）

`-Dgui` 编译完整的 w32 GUI 后端（HAVE_NTGUI：w32fns/w32term/w32font/
w32menu/w32select/w32uniscribe/w32xfns/w32cygwinx + fontset/fringe/image，
双 ABI 均支持）。图像格式按需开启（默认关，全部 zig fetch 自动下载源码、
哈希锁定、编译为静态库直接链入，无 DLL）：

```bash
# 全部六种格式 + GUI：
zig build -Dgui -Dwith-png -Dwith-jpeg -Dwith-tiff -Dwith-gif -Dwith-webp -Dwith-xpm

# MSVC 后端的 GUI（同样支持）：
zig build -Dgui -Dwith-png -Dwith-jpeg -Dwith-tiff -Dwith-gif -Dwith-webp -Dwith-xpm \
          -Dtarget=x86_64-windows-msvc
```

实测（双 ABI）：`image-type-available-p` 六种全 `t`，真实解码验证
png/jpeg/tiff/gif 1×1 → `(1 . 1)`、webp 550×368 样图 → `(550 . 368)`；
交互窗口正常打开（`-Q` 后 Win32 实测 689×671 可见窗口，与 MSYS2
参考构建形态一致）。libXpm 走上游 FOR_MSW 模拟层，无需任何 X11。

### 依赖版本更新（build.zig.zon）

所有第三方源码依赖集中在 `build.zig.zon` 的 `.dependencies` 表：每项
`.{ .url = ..., .hash = ..., .lazy = true }`（`lazy = true` 表示仅在
build.zig 实际用到时才下载）。更新版本三步：

1. 把 `.url` 改为新版本的 tarball 地址；
2. 删掉 `.hash` 行后运行 `zig fetch <新url>`——它下载源码并打印新的
   哈希字符串；
3. 把该字符串填回 `.hash`（保证可重现构建，离线缓存生效）。

镜像依赖同理（`tools/*/build.zig.zon` 各自维护自己的依赖）。

MSVC 后端已实测全量跑通：`zig build -Dtarget=x86_64-windows-msvc` 编译+链接+转储成功，
产出 `temacs.exe / emacs.exe / emacsclient.exe / etags.exe` 及完整 `bootstrap-emacs.pdmp`；
`etags --version` / `emacsclient --version` 可运行，且
**`zig build check -Dtarget=x86_64-windows-msvc` 全量 132 内置测试 0 unexpected，与 GNU 后端持平**。
MSVC 适配集中在"符号替换"层：完整
`nt/inc/stdint.h`（include_next 到 Zig stdint）、`nt/inc/sys/types.h`/`ms-w32.h` shim、
`build.zig` 的 MSVC 宏（`_USE_MATH_DEFINES`/`WINBOOL`/`ftello`/`__PRIPTR_PREFIX`）、
`alloc.c`/`config.h.in` 的 `_MSC_VER` 分支、`ENUM_BF`/`bool_bf` 与符号位域，以及提供 UCRT 缺失
POSIX 名的 Zig 包 `tools/msvc-posix`（详见 `TECHNICAL_VERIFICATION.md` §2.4）。GNU 后端全程不回归。

注意：`zig build help`、`zig build smoke`、`zig build check` 等步骤在
Windows 上通过 Zig 原生实现（不依赖 `/bin/echo` 或 shell），因此干净
Windows 环境即可运行端点步骤。MSVC 后端只能在 Windows 宿主上工作且必须
已安装 Windows SDK / VS Build Tools；选择 `-Dtarget=x86_64-windows-msvc` 时
`build.zig` 会打印一段 `choco install visualstudio2022buildtools
windows-sdk-10` 的安装提醒（不阻断构建；是否真缺工具链由 zig 自己的检测
决定，缺失时报 `WindowsSdkNotFound`）。

## 目录结构

```
build.zig                      # 主构建配置
build-aux/                     # 构建辅助脚本
└── extract-config.sh         # 提取版本和配置信息

zig-out/                       # 构建输出（运行 zig build 后生成）
├── bin/
│   ├── temacs                # Emacs可执行文件
│   ├── bootstrap-emacs.pdmp  # 便携式dump文件（字节编译镜像）
│   └── emacs                 # wrapper
├── etc -> ../etc             # dump 期 doc 解析所需的 sibling etc
└── libexec/emacs/31.0.50/aarch64-apple-darwin25.2.0/
    ├── emacs.pdmp
    └── emacs-31.0.50.pdmp
```

## 两阶段转储（为什么）

上游在最终转储前会字节编译 lisp；纯源码镜像会破坏依赖“已编译函数”的
行为（help-function-arglist 的 docstring 路径、cl-lib derived-type 方法
注册、cconv/loadhist 等）。因此 `compile-lisp` 用 bootstrap 转储把
`lisp/**/*.el` 编译为 `.elc`（增量，`byte-recompile-directory 0`），
`dump-compiled` 再跑一次 loadup 让最终镜像携带编译后的 preloaded 代码。
`check`/`check-all` 都依赖 `dump-compiled`。

## 清理缓存

```bash
# 清理构建缓存（保留核心配置）
./clean-caches.sh

# 手动清理
rm -rf .zig-cache zig-out
```

## 工作原理

### pdump发现机制

Emacs通过以下顺序查找pdump文件：

1. **argv[0]目录** - 与二进制文件相同的目录（优先）
2. **PATH_EXEC** - 硬编码路径（`/usr/local/libexec/...`）

我们将`temacs.pdmp`放在`zig-out/bin/`目录，确保Emacs能找到它。

### 已知问题和解决方案

| 问题 | 解决方案 |
|------|----------|
| pthread_sigmask递归崩溃 | 排除`lib/pthread_sigmask.c` |
| 模块编译错误 | 配置时使用`--without-modules` |
| 二进制过大(24MB) | 使用`-Doptimize=ReleaseFast` |
| pdump无法加载 | 将pdump与temacs放在同一目录 |

## 技术细节

### 编译器标志

```zig
// 核心宏定义
-Demacs=1
-DHAVE_PDUMPER=1
-DRELOAD0=0
-DHAVE_TTY=1
-DTERMINFO=1

// 平台特定
-D_DARWIN_C_SOURCE=1 (macOS)
-D_SYSTEM_TYPE="darwin"
-DAARCH64=1
```

### 链接库

**必需:**
- gmp, gnutls, sqlite3, xml2, z, lcms2, zstd

**macOS额外:**
- ncurses, pthread, iconv

## 故障排除

```bash
# 检查Zig版本（需要0.16.0）
zig version

# 清理并重新构建
./clean-caches.sh
zig build -Doptimize=ReleaseFast
```

## 后续计划

**Phase 2完成:**
- ✅ TUI-only构建
- ✅ pdump生成和加载
- ✅ 自包含zig-out/安装

**Phase 3（未来）:**
- ⏳ 完整autotools/Gnulib替换
- ⏳ Zig stdlib迁移
- ⏳ GUI支持（SDL3）

## 运行测试

### 基本测试

```bash
# 使用zig build运行测试
zig build test

# 或直接使用测试脚本
./run-emacs-tests.sh
```

### 手动运行特定测试

```bash
cd test

# 设置环境变量
export EMACS_TEST_DIRECTORY="$(pwd)"
export EMACS="../zig-out/bin/temacs"

# 运行特定测试
$EMACS --batch -l ert -l lisp/abbrev-tests.el -f ert-run-tests-batch-and-exit
```

### 测试结构

```
test/
├── lisp/           # Lisp测试文件
│   ├── abbrev-tests.el
│   ├── align-tests.el
│   └── ...
├── src/            # C源码测试
├── manual/         # 手册测试
└── infra/          # 测试基础设施
```

### 测试结果

测试日志保存在 `test/*.log` 文件中。

- **passed** - 测试通过 ✓
- **failed** - 测试失败 ✗
- **quit** - 测试退出

示例输出：
```
Ran 22 tests, 22 results as expected, 0 unexpected
```
