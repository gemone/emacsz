# zeln-jit: 进程内轻量 JIT（LuaJIT 思路）

状态：**进行中**（J1 地基已落地并通过测试）

## 目标

去掉 gcc/libgccjit 与重量级 LLVM 子进程（`zeln-compile` 每次 spawn +
`zig cc` 链接），为热点 Lisp 函数提供**进程内、零子进程、零磁盘**的
即时编译：参考 LuaJIT 的分层执行模型，但适配 Emacs 的字节码与
GC 约束。

## 架构（对照 LuaJIT）

| LuaJIT | zeln-jit | 说明 |
|---|---|---|
| 解释器（手写汇编 dispatch） | `exec_byte_code`（src/bytecode.c） | Tier 0，一切从这里开始 |
| hot count（指令内嵌计数） | closure 级调用计数（bytecode 入口递增） | 越过 `zeln-jit-threshold` 触发 Tier 1 |
| trace 编译（录制+回放） | **closure 整体编译**（M1 子集字节码） | Emacs 字节码较 Lua 更规则，closure 粒度即可获得收益；trace 录制留作后续 Tier 2 |
| 内嵌 assembler（机器码直出） | `tools/zeln-jit`（Zig x86-64 emitter） | 无 LLVM；代码写入 W^X 可执行 arena |
| JIT 缓存（GCO） | `ExecArena` + closure→code 哈希 | GC 交互：code 生命周期绑定 closure（后续接入 GC hook） |

### 关键复用：freloc ABI

生成的机器码与 `.zeln` 共用 `src/compz.c` 的 **freloc 链接表**
（102 个固定 C 入口：funcall/cons/car/cdr/arith/…）——通过
`base[IDX_*]` 间接调用，JIT 代码不需要任何 extern 符号，也不需要
`-rdynamic`。这保证：

1. JIT 代码与 AOT `.zeln` 行为一致（同一套 helper 语义）
2. 与 GC 安全（所有 Lisp 对象操作都经 freloc 的 C 入口，纪律与
   `.zeln` 相同）

## 分层计划

- **J1（已完成）**：`tools/zeln-jit` 地基
  - `ExecArena`：Linux memfd + RW/RX 双映射（W^X，现代 JIT 标准做法，
    V8/JSC 同款）；macOS MAP_JIT；其他平台 RWX 回退
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

## 测试

```
cd tools/zeln-jit && zig build test   # 3/3 pass
```

1. 常量函数生成执行（arena + emitter 基础）
2. 间接 call C 函数（freloc 调用形态原型）
3. 多段独立代码共存（per-closure 编译的原型）
