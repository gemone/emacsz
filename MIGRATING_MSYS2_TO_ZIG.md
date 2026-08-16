# 从 MSYS2/MinGW 迁移到 Zig 构建

本文档说明如何把 GNU Emacs 的 Windows 构建从传统的 **MSYS2 + Autoconf/Make + MinGW-GCC**
工具链迁移到本仓库的 **Zig 构建系统**（`build.zig`）。迁移完成后，一个 Windows 开发者
只需安装 **Zig 0.16**（外加可选的 Visual Studio C/C++ 工具链用于 MSVC 后端），执行
`zig build`，系统就会通过 `zig fetch` 自动下载并编译所有第三方 C 依赖——全程不触碰
MSYS2、MinGW 或任何 GNU 工具链。

相关文档：见 `ZIG_BUILD.md`（构建/选项/Windows 后端）、`INSTALL.REPO`（仓库构建说明）。

---

## 1. 为什么要迁移

| 旧方式 (MSYS2) | 新方式 (Zig) | 收益 |
|---|---|---|
| 需要安装 MSYS2 整套环境（`msys-2.0.dll`、`/usr/bin/*` 工具） | 只装一个 Zig 0.16 | 无 MSYS2 运行时依赖（目标 3.3） |
| C 编译器是 MinGW 的 `gcc.exe` | 用 `zig cc`（内置 MinGW/Clang 前端） | 摘除对 GCC 的硬依赖（目标 3.2） |
| 用 `./configure && make`（Autoconf/Make） | 用 `zig build`（构建图由 `build.zig` 描述） | 单入口、增量、可复现（目标 3.1） |
| 第三方库（zlib/libxml2/…）要手动装或用 MSYS2 包 | `build.zig.zon` 声明，`zig fetch` 自动下载 + `zig cc` 编译 | 依赖全自动（目标 3.5） |
| 只有 GCC ABI | 可自由切 GNU / MSVC 后端 | 双后端（目标 3.4） |

**验收对照**（目标编号见项目目标文档）：

- [ ] Windows 上仅需 Zig（GNU 后端）即可完整构建演示
- [ ] 可选 MSVC 后端需要 VS Build Tools / Windows SDK（目标 3.4 / 3.6）
- [ ] 所有 `--with-*` 特性开关都有 `-Dwith-*` 等效项（目标 3.1）
- [ ] 依赖通过 `zig fetch` 自动获取、哈希锁定、可离线（目标 3.5 / 2.2）

---

## 2. 前置条件

### 2.1 安装 Zig（两种方式任选）

用 Chocolatey（推荐，Windows 原生）：

```powershell
choco install zig --version=0.16.0
```

或用 pip/Compiled 二进制：

```powershell
winget install zig.zig  # 然后确保是 0.16.0
```

校验：

```powershell
zig version   # 要求 0.16.0（严格）
```

> 这就是**唯一**的硬依赖。不再需要 MSYS2、MinGW、Cygwin、Git-Bash。

### 2.2 可选：MSVC 后端需要的 VS 工具链

仅当你用 MSVC 后端时才需要（见 §5.2）。用 Chocolatey 安装 VS Build Tools + Windows SDK：

```powershell
# 需管理员 PowerShell
choco install -y visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools"
choco install -y windows-sdk-10
```

GNU 后端（默认）直接使用 Zig 内置的 MinGW 头文件和库，**不需要** VS 工具链。

---

## 3. 从旧流程迁移的快速对照

### 3.1 配置阶段

| 旧 | 新 |
|---|---|
| `./configure --prefix=... --with-native-compilation ...` | `zig build -Doptimize=Debug [-Dnative-comp=true ...]` |

`build.zig` 不再有独立 `./configure`：`src/config.h` 是构建的一个**一等构件**，由
`build.zig` 的 `b.addConfigHeader` 从提交的 `src/config.h.in` 模板 + `src/config_values.txt`
+ 每目标覆盖表 `config-overrides.zig` 生成。

### 3.2 编译 / 链接

| 旧 | 新 |
|---|---|
| `make -j8` | `zig build` |

`zig help`（或 `zig build help`）列出全部步骤与选项。

### 3.3 生成 bootstrap 数据（一次）

与 Make 流程一样，首次完整构建前生成字符集 / Unicode 数据（gitignored，`check`/`dump`
需要）。全部走 Zig 原生工具，无 `gawk`/`gunzip`/`sed`/shell：

```bash
zig build generate-charsets
zig build generate-unidata
zig build generate-charprop
zig build generate-cedet-grammars
```

### 3.4 转储 / 字节编译 / 冒烟

```bash
zig build dump           # 从源码转储 bootstrap-emacs.pdmp
zig build compile-lisp   # 字节编译 lisp/（增量）
zig build dump-compiled  # 用已编译 lisp 二次转储（最终镜像）
zig build smoke          # 验证转出的 emacs 能启动并求值 Lisp
```

`zig build smoke` 一条命令即可完成 dump → loaddefs → compile-lisp → dump-compiled → smoke。

### 3.5 测试

| 旧 | 新 |
|---|---|
| `make check` | `zig build check`（别名 `zig build test`） |
| `make check` 全部套件 | `zig build check-all` |

`zig build check` 运行 582 个内置 `ert` 测试（40 个套件）。

### 3.6 安装

| 旧 | 新 |
|---|---|
| `make install` | `zig build install`（默认步骤；产物在 `zig-out/`） |
| 指定目录 | `zig build -p <dir> install`（`-p/--prefix`，默认 `zig-out`）。**注意**：`-p` 目前只重定位可执行文件（`emacs.exe`/`temacs.exe`/`emacsclient.exe`/`etags.exe`）；转储镜像 `bootstrap-emacs.pdmp` 与运行时数据由 dump 步骤写在默认的 `zig-out/bin/`（`emacs` 启动器按自身位置找 pdmp）。因此自定义 `-p` 目录中的 `emacs.exe` 目前需手动连同 `zig-out/bin` 的 `bootstrap-emacs.pdmp`（和 `etc/`、loaddefs）一起拷贝才能运行；默认 `zig-out` 安装则完整可运行。 |

---

## 4. 构建选项对照

旧 `--with-*` / `--enable-*` 与新 `-D*`（用 `zig build -h` 查看最新列表）：

| 旧的 configure 选项 | 新的 `zig build` 选项（默认） | 说明 |
|---|---|---|
| `--with-native-compilation` | `-Dnative-comp=true` | gccjit 原生编译（.eln），native glibc-Linux only |
| （Zig 原生路径） | `-Dnative-comp-zig=true` | Zig/LLVM 原生编译（.zeln），glibc-Linux only |
| `--with-gnutls` | `-Dwith-gnutls`（on） | GnuTLS，vendored via `zig fetch` |
| `--with-sqlite3` | `-Dwith-sqlite3`（on） | SQLite，vendored |
| `--with-libxml2` | `-Dwith-xml2`（on） | libxml2，vendored |
| `--with-lcms2` | `-Dwith-lcms2`（on） | Little CMS，vendored |
| `--with-zlib` | `-Dwith-zlib`（on） | zlib，vendored |
| `--with-tree-sitter` | `-Dwith-tree-sitter`（on） | tree-sitter，vendored；设 false 时不链接库且 `treesit-available-p` 报不可用 |
| `--with-dbus` | `-Dwith-dbus` | Linux/macOS 专属 |
| `--with-gpm` | `-Dwith-gpm` | Linux 专属 |
| `--with-alsa` | `-Dwith-alsa` | Linux 专属 |
| `--with-acl` | `-Dwith-acl` | POSIX ACL |
| `--with-modules` | `-Dmodules` / `-Dmodules-zig` | 动态模块 |
| `--with-x-toolkit` 等 | 不适用（TTY / w32 console） | GUI/Windowing 不在本方案范围 |

用 `-Dwith-*=false` 关闭某个默认开启的特性，例如：

```bash
zig build -Dwith-zlib=false
```

> 注意：特性开关会同步剔除 `EMACS_CONFIG_FEATURES` 中对应的 token，保证 `M-x
> emacs-version` 等上报的特性真实。

---

## 5. Windows 后端安装配置指南

### 5.1 GNU/MinGW 后端（默认，仅需 Zig）

Windows 本机目标即 `x86_64-windows-gnu`，直接：

```powershell
zig build            # 默认 GNU 后端（zig 内置 MinGW 头文件+库）
zig build smoke
zig build check
zig-out\bin\emacs.exe --version   # 验证产物
```

不需要任何额外工具链。产物包括 `zig-out/bin/temacs.exe`、`zig-out/bin/emacs.exe`
（原生 exe 启动器，非 shell 脚本）、`bootstrap-emacs.pdmp`。

### 5.2 MSVC 后端（可选，需 VS 工具链）

先按 §2.2 安装 VS Build Tools + Windows SDK，然后：

```powershell
zig build -Dtarget=x86_64-windows-msvc
```

- 只能在 **Windows** 宿主上工作，且必须已安装 Visual Studio / Windows SDK。
- 选择 MSVC 后端时 `build.zig` 会打印 `choco install visualstudio2022buildtools
  windows-sdk-10` 的安装提醒（不阻断构建）；工具链是否真的缺失由 zig 自己的检测决定，
  缺失时报 `WindowsSdkNotFound`。

显式指定 GNU 后端写法等价：`zig build -Dtarget=x86_64-windows-gnu`。

---

## 6. 依赖管理（`zig fetch` / `build.zig.zon`）

所有第三方 C 源码依赖都在 `build.zig.zon` 的 `.dependencies` 里按名声明，每项给
`url`（GitHub release / 官方 tarball）和 `hash`（内容寻址，版本锁定）。`zig build` 首次
构建时自动下载、校验、缓存到全局缓存（离线可复用）；`build.zig` 通过
`b.dependency("名称", .{})` 取得解压后的路径，用 `zig cc` 编成静态库链接进 `temacs`。

当前已 vendored（Windows/全平台会用到的）：

| 依赖名（zon 键） | 用途 |
|---|---|
| `.zlib_src` | zlib 压缩 |
| `.sqlite_src` | SQLite 数据库 |
| `.lcms2_src` | Little CMS 色彩管理 |
| `.tree_sitter` | tree-sitter 语法解析 |
| `.xml2_src` | libxml2 XML 解析 |
| `.nettle_src` / `.gnutls_src` | GnuTLS 后端（macOS built；lazy） |
| `.ncurses_src` | ncurses terminfo（macOS） |

### 6.1 更新某个依赖的版本

1. 改 `build.zig.zon` 里对应的 `url`。
2. 用 `zig fetch <新 URL>`（或在仓库根执行 `zig build`，它会给出一行提示），会打印新的
   `hash`。
3. 把打印的 `hash` 填回 `build.zig.zon` 该依赖的 `.hash` 字段。
4. 若新版本改了 API/构建方式，同步更新 `build.zig` 里该依赖的源文件列表 /
   `addCSourceFile` / `addIncludePath` 等。

> 变更记录在 `build.zig` 中相应 `with_*` 块上方的注释里（例如 libxml2 / zlib 的
> vendored 集成说明）。

可复现保证：

- 每个依赖固定 `url` + `hash` → 相同 `build.zig.zon` 每次构建得到源码相同。
- 首次构建联网；之后走全局缓存，支持离线 / 无 MSYS2 环境。

### 6.2 新增一个依赖（例如未来的 imagen libpng）

1. 在 `build.zig.zon` `.dependencies` 加一项（name = `png_src`，url + hash）。
2. 在 `build.zig` 建一个独立 module（`b.createModule`），加入源文件与 include 路径，
   `b.addLibrary` 成静态库，`exe.root_module.linkLibrary(...)`。
3. 在 `config-overrides.zig` / `config.h` 里打开对应特性宏（如 `HAVE_PNG`）。

---

## 7. 从 MSYS2 迁移到 Zig 的迁移指南（分步）

对现有 MSYS2 工作区做最小改动切换到 Zig 构建：

1. **保留源码树**：无需重新 clone；本仓库的 `build.zig` / `build.zig.zon` 与
   `configure.ac` / `Makefile.in` 并存，`zig build` **非侵入**（只在缓存与
   `zig-out/` 写产物；`src/config.h` 是构建期生成的 gitignored 构件）。
2. **清掉旧的配置产物**（可省）：
   ```powershell
   Remove-Item .zig-cache, zig-out -Recurse -Force -ErrorAction SilentlyContinue
   ```
3. **装 Zig**（§2.1），可选装 VS 工具链（§2.2）。
4. **跑数据生成**（§3.3，每次 clone 一次）。
5. **`zig build`** 编译链接 `temacs.exe` + `emacs.exe`。
6. **`zig build smoke`** 验证可运行，**`zig build check`** 跑测试。
7. **验证产物**：
   ```powershell
   zig-out\bin\emacs.exe --version
   ```
8. 从 CI/脚本里把 `./configure && make && make install` 替换成
   `zig build [install]`；Windows 上用 PowerShell 作为默认 shell（无需 Git-Bash）。

**迁移验收清单**（对应目标 §五/§七）：

- [ ] 纯 Windows 干净环境（无 MSYS2/MinGW/GCC），仅 Zig → `zig build` 成功出 `emacs.exe`
- [ ] `zig build check` 全绿
- [ ] 产物 `emacs.exe` 可正常运行
- [ ] 可选 MSVC 后端（装了 VS 工具链后）`zig build -Dtarget=x86_64-windows-msvc` 可尝试

---

## 8. 故障排查

| 症状 | 处理 |
|---|---|
| `zig: command not found` | 安装 Zig 0.16 并加入 PATH（§2.1） |
| `MSVC 后端需要 Windows SDK...` 报错 | 装 VS Build Tools + Windows SDK（§2.2）后重跑 |
| `zig build check` 报数据缺失 | 先跑 §3.3 的数据生成步骤 |
| 想清掉缓存重来 | `Remove-Item .zig-cache, zig-out -Recurse -Force` |
| 依赖下载失败（首次联网） | 检查网络；已缓存后本地构建不再需要联网（§6.1） |
