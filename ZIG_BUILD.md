# Emacs Zig Native Build System

这是GNU Emacs的Zig原生构建系统，作为Phase 2的一部分，提供TUI-only构建。

## 快速开始

```bash
# 1. 配置Emacs（禁用GUI和模块）
./configure --without-ns --without-x --without-modules

# 2. 使用Zig构建
zig build -Doptimize=ReleaseFast

# 3. 运行
./zig-out/bin/temacs --batch --eval '(progn (message "Hello, World!") (kill-emacs))'
```

## 构建选项

- `-Doptimize=Debug` - 调试模式（默认，较大）
- `-Doptimize=ReleaseFast` - 优化发布（推荐，2.7MB）
- `-Doptimize=ReleaseSafe` - 安全发布
- `-Doptimize=ReleaseSmall` - 最小体积
- `-Dtarget=<triple>` - 交叉编译（例如：x86_64-linux-gnu）

## 目录结构

```
build.zig                      # 主构建配置
build-aux/                     # 构建辅助脚本
└── extract-config.sh         # 提取版本和配置信息

zig-out/                       # 构建输出（运行 zig build 后生成）
├── bin/
│   ├── temacs                # Emacs可执行文件 (2.7MB)
│   ├── temacs.pdmp           # 便携式dump文件 (12MB)
│   ├── etc -> ../../etc      # 符号链接
│   └── lib-src -> ../../lib-src
└── libexec/emacs/31.0.50/aarch64-apple-darwin25.2.0/
    ├── emacs.pdmp
    └── emacs-31.0.50.pdmp
```

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

