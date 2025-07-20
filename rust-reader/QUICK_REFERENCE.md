# Rust Reader 快速参考

## 🚀 快速开始

### 1. 环境准备
```bash
# 进入项目目录
cd /Users/liheng/work/github/koreader/rust-reader

# 进入 Nix 环境
nix-shell
```

### 2. 开发流程
```bash
# 1. 编辑代码
vim src/main.rs

# 2. 编译并部署
nix-shell --run "./build-kindle.sh"

# 3. 运行测试
ssh -F ssh-config kindle "cd /mnt/us && ./kindle-reader"

# 4. 拉取日志
scp -F ssh-config kindle:/mnt/us/*.log .

# 5. 分析结果
cat *.log
```

## 📋 常用命令

### 编译相关
```bash
# 本地编译
cargo build
cargo build --release

# ARM 交叉编译
cargo build --release --target arm-unknown-linux-musleabihf

# 启用 GTK 功能
cargo build --release --target arm-unknown-linux-musleabihf --features gtk

# 清理构建
cargo clean
```

### 部署相关
```bash
# 自动构建和部署
./build-kindle.sh

# 手动部署
scp -F ssh-config target/arm-unknown-linux-musleabihf/release/kindle-reader kindle:/mnt/us/
ssh -F ssh-config kindle "chmod +x /mnt/us/kindle-reader"
```

### 测试相关
```bash
# SSH 连接
ssh -F ssh-config kindle

# 运行程序
cd /mnt/us
./kindle-reader

# 后台运行
nohup ./kindle-reader > output.log 2>&1 &

# 查看进程
ps aux | grep kindle-reader
```

### 日志相关
```bash
# 拉取日志
scp -F ssh-config kindle:/mnt/us/*.log .

# 实时查看日志
ssh -F ssh-config kindle "tail -f /mnt/us/*.log"

# 查看程序输出
ssh -F ssh-config kindle "cat /mnt/us/output.log"
```

## 🔍 诊断命令

### 系统状态
```bash
# 检查显示管理器
ssh -F ssh-config kindle "ps aux | grep -E '(dmld|Xorg|awesome|blanket)'"

# 检查 framebuffer
ssh -F ssh-config kindle "lsof /dev/fb0"
ssh -F ssh-config kindle "cat /sys/class/graphics/fb0/virtual_size"

# 检查环境变量
ssh -F ssh-config kindle "env | grep -E '(DISPLAY|GTK)'"
```

### 库文件检查
```bash
# 检查 GTK 库
ssh -F ssh-config kindle "ls -la /usr/lib/libgtk*"

# 检查 Cairo 库
ssh -F ssh-config kindle "ls -la /usr/lib/libcairo*"

# 检查程序依赖
ssh -F ssh-config kindle "ldd /mnt/us/kindle-reader"
```

## 🛠️ 问题解决

### 编译问题
```bash
# 问题: 编译失败
# 解决: 确保在 Nix 环境中
nix-shell
cargo clean
cargo build --release --target arm-unknown-linux-musleabihf
```

### 部署问题
```bash
# 问题: SSH 连接失败
# 解决: 检查网络和配置
ping 192.168.1.5
cat ssh-config
ssh -F ssh-config kindle "echo 'test'"
```

### 显示问题
```bash
# 问题: 屏幕没有变化
# 解决: 检查显示环境
ssh -F ssh-config kindle "ps aux | grep -E '(Xorg|awesome)'"
ssh -F ssh-config kindle "lsof /dev/fb0"
ssh -F ssh-config kindle "cat /sys/class/graphics/fb0/blank"
```

## 📊 测试结果记录

### 测试1: Framebuffer 直接访问
- **状态**: ❌ 失败
- **问题**: 显示管理器覆盖写入
- **日志**: `simple_test.log`

### 测试2: X11 环境测试
- **状态**: ❌ 不稳定
- **问题**: DISPLAY 变量不稳定
- **日志**: `x11_test.log`

### 测试3: GTK 环境测试
- **状态**: ✅ 部分成功
- **发现**: GTK 库存在，需要启用功能
- **日志**: `gtk_test.log`

## 🎯 下一步行动

### 立即行动
1. 启用 GTK 功能重新编译
2. 设置 DISPLAY 环境变量
3. 创建 GTK Hello World 窗口

### 本周目标
- [ ] 完成 GTK 基础实现
- [ ] 验证显示可行性
- [ ] 开始 Cairo 研究

---

*快速参考版本: 1.0*  
*最后更新: 2024-07-19* 