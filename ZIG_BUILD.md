# Emacs Zig Native Build System

这是GNU Emacs的Zig原生构建系统，作为Phase 2的一部分，提供TUI-only构建。

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

- `-Doptimize=Debug` - 调试模式（默认，**目前唯一可靠**）
- `-Dtarget=<triple>` - 交叉编译（例如：x86_64-linux-gnu）
- `-Dnative-comp=[bool]` - gccjit 原生编译路径（.eln，`HAVE_NATIVE_COMP`，
  `src/comp.c`）。默认 OFF。仅在本机 glibc-Linux 上生效（libgccjit 是宿主
  库，不能交叉编译）；非本机/musl/windows/macos 自动关闭。开启需要系统
  安装 libgccjit（链接 `-lgccjit`），且 `libgccjit.h` 的 include 路径在构建
  时通过 `cc -print-file-name=include` 推导。
- `-Dnative-comp-zig=[bool]` - Zig/LLVM 原生编译路径（.zeln，
  `HAVE_NATIVE_COMP_ZIG`，`src/compz.c`）。默认 OFF。仅在本机 glibc-Linux 上
  生效。与 `-Dnative-comp` **相互独立**，两者可同时开启（M2.5 共存）。

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

注意：`ReleaseFast`/`ReleaseSafe` 目前会让 temacs 在加载转储时崩溃
（clang -O1+ 暴露了 pdumper 单-delta 重定位的缺陷）。在深层 pdumper
多-delta 修复完成之前，请使用默认的 Debug（-O0）。

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
