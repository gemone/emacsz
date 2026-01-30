# Emacs Zig Build - 测试指南

## 快速开始

```bash
# 1. 构建Emacs
./configure --without-ns --without-x --without-modules
zig build -Doptimize=ReleaseFast

# 2. 运行测试
zig build test

# 或使用测试脚本
./run-emacs-tests.sh       # 快速测试
./run-all-tests.sh         # 测试套件
```

## 测试命令

### 通过zig build

```bash
zig build test              # 运行默认测试
```

### 直接运行测试脚本

```bash
./run-emacs-tests.sh        # 运行abbrev-tests (快速验证)
./run-all-tests.sh          # 运行测试套件
```

### 手动运行特定测试

```bash
cd test

# 设置环境
export EMACS_TEST_DIRECTORY="$(pwd)"
export EMACS="../zig-out/bin/temacs"

# 运行测试
$EMACS --batch \
    -L "$(pwd)/lisp" \
    -L "$(pwd)/../lisp" \
    -l ert \
    -l lisp/abbrev-tests.el \
    -f ert-run-tests-batch-and-exit
```

## 测试输出

### 成功示例
```
Ran 22 tests, 22 results as expected, 0 unexpected
```

### 测试日志
- `test/abbrev-tests.log` - abbrev测试日志
- `test/buff-menu-tests.log` - buff-menu测试日志

## 可用的测试

### Lisp测试 (test/lisp/)

| 测试文件 | 描述 | 状态 |
|---------|------|------|
| abbrev-tests.el | 缩写功能 | ✓ |
| buff-menu-tests.el | 缓冲区菜单 | ✓ |
| buffer-tests.el | 缓冲区操作 | ⚠️ |

更多测试见 `test/lisp/` 目录。

## 故障排除

### 测试失败

1. **检查temacs是否构建**
   ```bash
   ls -lh zig-out/bin/temacs
   ```

2. **检查pdump文件**
   ```bash
   ls -lh zig-out/bin/temacs.pdmp
   ```

3. **查看详细错误日志**
   ```bash
   cat test/*.log
   ```

### 路径问题

如果看到 "Cannot open load file" 错误：
- 确保使用了 `-L "$(pwd)/lisp"` 参数
- 检查 `EMACS_TEST_DIRECTORY` 是否正确设置

## 高级用法

### 运行所有Lisp测试

```bash
cd test
for test in lisp/*-tests.el; do
    name=$(basename "$test" .el)
    echo "Running $name..."
    $EMACS --batch \
        -L "$(pwd)/lisp" \
        -L "$(pwd)/../lisp" \
        -l ert -l "$test" \
        -f ert-run-tests-batch-and-exit \
        | tee "$name.log"
done
```

### 并行运行测试

```bash
# 注意: Emacs测试不建议并行运行
make -C test check  # 使用autotools（如果已配置）
```

## 参考资料

- [ERT文档](https://www.gnu.org/software/emacs/manual/html_node/ert/)
- [test/README](test/README) - 官方测试文档
- [ZIG_BUILD.md](ZIG_BUILD.md) - 构建系统文档
