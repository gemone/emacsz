# zeln-jit: 进程内轻量 JIT（LuaJIT 思路）

状态：引擎 J1–J6 已落地；当前运行时门保持 opt-in（`ZELN_JIT=1`），
用于完成真实错误路径/展开审计后再切回默认开启。构建工具链默认仍
写 `ZELN_JIT=0`；专用 `zeln-jit-smoke` 门再在自己的运行时子进程里
显式打开。

## 目标

去掉 gcc/libgccjit 与重量级 LLVM 子进程（`zeln-compile` 每次 spawn +
`zig cc` 链接），为热点 Lisp 函数提供**进程内、零子进程、零磁盘**的
即时编译：参考 LuaJIT 的分层执行模型，但适配 Emacs 的字节码与
GC 约束。

## 架构（对照 LuaJIT）

| LuaJIT | zeln-jit | 说明 |
|---|---|---|
| 解释器（手写汇编 dispatch） | `exec_byte_code`（src/bytecode.c） | Tier 0，一切从这里开始 |
| hot count（指令内嵌计数） | closure 级调用计数（bytecode 入口递增） | 越过 `zeln-jit-threshold` 触发 Tier 1；默认 256，可在运行时调优 |
| trace 编译（录制+回放） | **closure 整体编译**（M1 子集字节码） | Emacs 字节码较 Lua 更规则，closure 粒度即可获得收益；trace 录制留作后续 Tier 2 |
| 内嵌 assembler（机器码直出） | `tools/zeln-jit`（Zig x86-64 emitter） | 无 LLVM；代码写入 W^X 可执行 arena |
| JIT 缓存（GCO） | `ExecArena` + closure→code 哈希 | GC 交互：code 生命周期绑定 closure（后续接入 GC hook） |

### 关键复用：freloc ABI

生成的机器码与 `.zeln` 共用 `src/compz.c` 的 **freloc 链接表**
（103 个固定 C 入口：funcall/cons/car/cdr/arith/…）——通过
`base[IDX_*]` 间接调用，JIT 代码不需要任何 extern 符号，也不需要
`-rdynamic`。这保证：

1. JIT 代码与 AOT `.zeln` 行为一致（同一套 helper 语义）
2. 与 GC 安全（所有 Lisp 对象操作都经 freloc 的 C 入口，纪律与
   `.zeln` 相同）

## 分层计划

- **J1（已完成）**：`tools/zeln-jit` 地基
  - `ExecArena`：Linux memfd + RW/RX 双映射（W^X，现代 JIT 标准做法，
    V8/JSC 同款）；macOS MAP_JIT；Windows VirtualAlloc；其他平台 RWX 回退
  - WinX64 展开：为每个 JIT 函数注册 `RUNTIME_FUNCTION`，让 Lisp error
    穿过 JIT 帧时系统 unwinder 能识别 prologue
  - 架构门：手写 emitter 目前只支持 x86-64。`ZELN_JIT_ARCH_X86_64`
    未定义的构建（例如 AArch64 Linux/macOS）永远回退解释器/AOT，
    环境变量不能把错误架构机器码带进进程
  - `X86` emitter：REX/imm64/mov/call/ret/add 最小指令集
  - 单测证明进程内生成并**真实执行**机器码（含通过寄存器间接
    call 一个 C 函数——freloc 调用形态的原型）
- **J2**：热点检测——`exec_byte_code` 入口处按 closure 计数，
  越过阈值调用 C ABI shim（compz.c）进入 JIT
- **J3**：字节码→机器码编译器——移植 `zeln-compile` 的 M1
  操作码子集逻辑，从"发射 LLVM IR"改为"发射机器码"
  （虚拟栈 over alloca 的布局先沿用，SSA 化后置）
- **J4**：执行替换与回退——编译产物挂在 closure 上，调用走
  machine code；任何编译失败静默回退解释器（与 populate 的
  skip 语义一致）
- **J5**：GC 集成与 arena 回收
- **J6**：基准对比（fib/散列/真实套件 vs 解释器 vs .zeln AOT）

## 为什么不直接复用 zeln-compile（LLVM）

- 每次 spawn + `zig cc -shared` 约 ~百毫秒级 + 磁盘产物，做不了
  "热点触发"的交互式 JIT（用户可感知的停顿）
- LLVM 优化对 Emacs 字节码的收益有限（热点是 dispatch 与 Lisp
  对象操作，而非循环不变量）；LuaJIT 证明手写轻量代码生成 +
  分层足以赢
- 进程内 arena 使"编译→立即执行→失败回退"成为廉价路径

## 实测性能（J4 完成后，ZELN_JIT=1）

| workload | 解释器 | 进程内 JIT | 加速 |
|---|---|---|---|
| fib 22（递归、分支、自调用） | ~0.080s | ~0.037s | **2.2×** |
| cons/乘法循环 n=1200 | 0.0122s | 0.0067s | **1.8×** |
| 字符串 concat 循环 n=400 | 0.0577s | 0.0026s | **22×**（GC 1→0） |
| let/while+setq 循环 n=100000 | 0.0763s | 0.0407s | **1.87×** |

测量：best-of-3 ×3 次稳定；`(zeln-jit-compiled-p f)` = t 证实走 JIT。
注意 shell 栈 rlimit 需正常（本测试机 ulimit -s 65536；16KB 的异常
环境会限制递归深度，与 JIT 无关）。

### 可复现 A/B 门

为了防止"解释器基线"在同一个进程里被热点计数悄悄替换成 JIT，`zeln-bench-run'
现在为 JIT 建立独立的 bytecode/consts 对象，并在计时前确认
`zeln-jit-compiled-p' 为 t；解释器侧则把阈值调高。同一个 workload 会先做
interpreter/AOT/JIT 结果一致性检查，然后输出三条 geomean：

```bash
zig build -Dnative-comp-zig=true zeln-jit-bench
```

2026-08-30 Linux/x86-64 本机结果（JIT-to-JIT call fast path 后，best-of-3，
10 个 workload）：

| ratio | value | meaning |
|---|---:|---|
| AOT / interpreter | 0.210 | AOT 比 interpreter 快约 4.8x |
| JIT / interpreter | 0.250 | JIT 比 interpreter 快约 4.0x |
| AOT / JIT | 0.839 | AOT 约快 19%，差距进一步收窄 |

因此 JIT 的 Tier-0→Tier-1 收益已经可复现。`Bcall' 现在经过
`zeln-jit-call'：只有 closure object 本身、或 bare symbol 解析后的
closure、且二者都满足 exact fixed arity 和已有 validated JIT entry 时，
才直接进入该 entry；其它所有形态 fallback 到原 `funcall_general'。
AOT `.zeln' 的 `Bcall' 也统一走这个 helper，因此原生 AOT caller 调用
热点 Lisp closure 时同样能保留 JIT Tier-1；非 JIT callee 的行为仍与
旧的 `zeln-funcall` 路径一致。

在 eln+zeln 共存构建中，`.zeln' subr 现在携带与 `.eln` 相同的
native-comp-unit 元数据：`native-comp-function-p'、
`subr-native-comp-unit' 与 `native-comp-unit-file' 可识别并报告 `.zeln'。
这让 help/introspection 与 native artifact 工具链无需 backend 分支；
zeln-only 构建仍保持原来的 plain-subr 兼容路径。
这项改动主要改善 recursive/hot-symbol-call 场景（fib 的
JIT/interpreter 从约 0.575 降到 0.349）；剩余差距主要来自未内联的
hash/字符串等热点 helper。
不要把这组数据与上方历史 microbench 直接混用。

## 门控与验证（J6）

引擎曾在真实 Lisp 错误/展开路径中发现跨平台缺陷，因此当前门保持
opt-in。`ZELN_JIT=1` 启用（仅 x86-64）；`ZELN_JIT=0` 显式关闭。
构建管线始终设置关闭，JIT 冒烟门单独打开。验证矩阵：

- 全量 check（40 套件 / 582 测试）：0 unexpected
- dump-compiled 管线、check-zeln（AOT 门）、check-zeln-jit（AOT+JIT 门）、
  serialize walk（2296 文件）：全绿
- `zeln-jit-bench`：interpreter/AOT/JIT 三方结果一致，且每个 JIT clone
  都必须真实进入 machine-code dispatch
- freloc surface 追加 `zeln-jit-call'（idx 102，总数 103）；沿用
  append-only ABI 规则，位置与旧索引不变
- `zeln-jit-stats` 第五项为 FAST-CALLS，直接证明 guarded tier-to-tier
  call 真实发生
- 四基准（无环境变量）：fib 1.7×、let/while 1.7×、cons/mul 2.1×、concat 22×
- 默认（gccjit）构建不受影响（gate 仅在 zeln 构建编译）

当前 `Bplus'/`Bdiff'/`Bmult' 以及 `Bsub1'/`Badd1'/`Bnegate' 使用与 AOT M3a
相同语义的 tagged fixnum inline fast path；
non-fixnum、float、bignum 与 fixnum overflow 都落到同一个 frozen freloc helper。
该 fast path 的关键不变量是二进制 opcode 必须净弹出 1 个栈位（结果写入
`TOP-1'）。单元测试与真实 suite 中重复执行 `pp-fill' 都覆盖了这个 case。
`Bmult' 使用 x86-64 signed `imul' 的 CF/OF overflow 语义；对两个合法 fixnum
而言，该检查与 61-bit fixnum range check 一致。

`Beqlsign'/`Bgtr'/`Blss'/`Bleq'/`Bgeq' 也使用 tagged fixnum inline fast path。
硬件比较在解码后的 `(v2,v1)' 上执行，因此 GT/LT 和 LE/GE 的条件码做镜像；
布尔结果使用 runtime 传入的 canonical `Qt' raw word 或 `Qnil=0'。非 fixnum
继续走同一个 freloc helper。

`Bcar'/`Bcdr' 已启用 tagged cons-slot fast path：`CONSP' 通过低 3 位
判定，`XCAR'/`XCDR' 直接读取清 tag 后的 cons 槽位；nil 和非 cons 仍
进入同一个 freloc helper，完整保留错误和 `safe-car'/`safe-cdr' 语义。
引擎级测试同时覆盖 CAR/CDR fast path 与 non-cons fallback；此前的
临时 fake-cons 诊断已移除。

`Bconsp'/`Bnot' 也已对齐 AOT M3c：二者是 total pure predicate，JIT
直接用 `CONSP' tag test / `NILP' zero test 生成 canonical `Qt'/`Qnil'，
不再调用 freloc helper；引擎级测试覆盖 cons/non-cons/nil/non-nil。
`Bsymbolp'/`Bstringp'/`Blistp'/`Bnumberp'/`Bintegerp' 增加了 tagged
representation fast path；未被 immediate tag 识别的输入（symbol-with-pos、
bignum、float 等）仍进入原 freloc helper，保持完整语义。

## 测试

```
cd tools/zeln-jit && zig build test   # 24/24 pass
zig build -Dnative-comp=false -Dnative-comp-zig=true zeln-jit-unit
zig build -Dnative-comp=false -Dnative-comp-zig=true zeln-jit-smoke
zig build -Dnative-comp=false -Dnative-comp-zig=true check-zeln-jit
zig build -Dnative-comp=true -Dnative-comp-zig=true zeln-jit-smoke
zig build -Dnative-comp=true -Dnative-comp-zig=true zeln-interop-smoke
```

JIT 全量门显式关闭 gccjit：这样即使构建主机恰好装有 libgccjit，
也不会因 combined 路径的 lazy documentation 交互而改变被测对象。
combined 构建由单独的 metadata/interop 门验证。

引擎级测试：

1. 常量函数生成执行（arena + emitter 基础）
2. 间接 call C 函数（freloc 调用形态原型）
3. 多段独立代码共存（per-closure 编译的原型）
4. 同 bytecode、fresh constants 的重建 closure 立即获得自己的 JIT
   entry 并 pin 新 closure；不会读取别的 closure 的 constants，也不会
   永久留在解释器里
5. `Bswitch` 通过与 AOT 相同的 `zeln-switch-target` helper 解析；
   pcase 等 jump-table bytecode 不再被迫留在解释器
6. `BdiscardN` 覆盖普通 discard 和保留 TOP 的 discard-and-preserve 语义
7. JIT 与 AOT 的 M1/M2 freloc opcode 覆盖对齐，含类型谓词、equal/eq、
   max/min、list 构造、buffer/region 操作、push0/noarg 与 unwind-protect
8. `Bcar'/`Bcdr' 的 cons-slot inline、non-cons freloc fallback，以及
   CAR/CDR 两个槽位的结果都真实执行验证
9. `zeln-jit-smoke` 用 symbol-dispatched Fibonacci 覆盖 JIT→JIT 递归
   fast path、结果一致性与 `zeln-jit-compiled-p'
10. `zeln-jit-smoke` 用 higher-order closure 覆盖 closure-object call
    的 cold fallback、JIT adoption 和后续 fast path
11. `zeln-jit-smoke` 编译并加载原生 AOT caller，绑定 JIT callee，并检查
    FAST-CALLS 计数增加，覆盖 AOT→JIT seam
12. `Bconsp'/`Bnot' 的 inline predicate 在 cons/non-cons 和 nil/non-nil
    输入上都真实执行验证
13. `Bsymbolp'/`Bstringp'/`Blistp'/`Bnumberp'/`Bintegerp' 的 immediate
    fast path 与 freloc fallback 都用真实输入执行验证
14. combined eln+zeln 构建中，AOT fixture 会检查
    `native-comp-function-p' 与 `native-comp-unit-file' 返回 `.zeln'
15. NOJIT cache entry 也通过 closure pin list 保持 bytecode key 生命周期，
    避免 rejected closure 被 GC 后造成 stale-key 复用
