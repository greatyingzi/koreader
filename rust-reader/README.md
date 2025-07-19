# Kindle 极简阅读器

基于 Rust 开发的极简 Kindle 阅读器，直接操作 framebuffer 和输入设备。

## 功能特性

- ✅ 支持 UTF-8 文本文件阅读
- ✅ 触摸屏翻页（左半屏上一页，右半屏下一页）
- ✅ 按键翻页（方向键、PageUp/PageDown）
- ✅ 全屏刷新显示
- ✅ 自动分页
- ✅ 页码显示
- ✅ 8x8 点阵字体渲染

## 编译和运行

### 前提条件

- Rust 工具链
- 目标设备：Kindle 或其他 Linux 设备
- 需要 root 权限访问 `/dev/fb0` 和 `/dev/input/event*`

### 使用 Nix 编译环境（推荐）

如果您使用 macOS 或 Linux 并安装了 Nix，可以使用我们提供的 Nix 环境：

```bash
# 进入 Nix 编译环境
cd rust-reader
nix-shell

# 编译 ARM 版本（用于 Kindle）
./build-kindle.sh

# 编译本地版本（用于测试）
cargo build --release

# 运行本地版本
cargo run test_book.txt
```

### 传统编译方式

```bash
# 本地编译（用于测试）
cargo build --release

# 交叉编译到 ARM (Kindle)
# 需要先安装交叉编译工具链
rustup target add arm-unknown-linux-gnueabihf
cargo build --release --target arm-unknown-linux-gnueabihf --no-default-features --features embedded
```

### 运行

```bash
# 基本用法
./target/release/kindle-reader /path/to/your/book.txt

# 在 Kindle 上运行
./kindle-reader /mnt/us/documents/book.txt
```

### 环境变量配置

可以通过环境变量调整屏幕参数：

```bash
export KINDLE_WIDTH=1448
export KINDLE_HEIGHT=1072
export KINDLE_BPP=1
./kindle-reader book.txt
```

## 部署到 Kindle

### 1. 传输文件

```bash
# 使用 SCP 传输（需要 SSH 访问）
scp target/arm-unknown-linux-gnueabihf/release/kindle-reader root@kindle:/mnt/us/

# 或者使用 USB 连接复制到 Kindle
```

### 2. 设置权限

在 Kindle 上执行：

```bash
chmod +x /mnt/us/kindle-reader
sudo chmod 666 /dev/fb0 /dev/input/event*
```

### 3. 运行

```bash
./kindle-reader /mnt/us/documents/book.txt
```

## 操作说明

### 翻页操作

- **触摸屏**：点击左半屏上一页，右半屏下一页
- **按键**：
  - 上一页：PageUp, 左箭头, 上箭头
  - 下一页：PageDown, 右箭头, 下箭头
  - 退出：ESC, Q

### 支持的文件格式

目前仅支持纯文本文件（.txt），编码为 UTF-8。

## 架构设计

```
main.rs          # 主程序入口和事件循环
├── framebuffer  # 屏幕显示管理
├── input        # 输入设备处理
├── font         # 字体渲染
└── pager        # 文本分页
```

## 技术实现

- **framebuffer**：直接内存映射 `/dev/fb0` 设备
- **输入处理**：监听 Linux input events
- **字体渲染**：使用 8x8 点阵字体
- **分页算法**：基于字符数自动分页
- **屏幕刷新**：使用 mxcfb ioctl 触发刷新

## 已知限制

1. 仅支持 ASCII 字符显示（8x8 字体限制）
2. 不支持中文等宽字符
3. 固定字体大小
4. 简单的分页算法
5. 无菜单界面

## 扩展计划

- [ ] 支持更多字符集
- [ ] 可配置字体大小
- [ ] 书签功能
- [ ] 搜索功能
- [ ] 更智能的分页算法
- [ ] 支持 EPUB 格式

## 故障排除

### 权限问题
```bash
# 确保有权限访问设备
sudo chmod 666 /dev/fb0
sudo chmod 666 /dev/input/event*
```

### 屏幕不刷新
- 检查 mxcfb ioctl 是否支持
- 某些设备可能需要不同的刷新方式

### 输入设备未找到
- 检查 `/dev/input/` 目录下的设备文件
- 使用 `evtest` 工具测试输入设备

## 许可证

MIT License 