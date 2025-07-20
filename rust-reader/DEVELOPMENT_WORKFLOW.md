# Rust Reader 开发流程记录

## 项目概述

**项目名称**: Rust Reader for Kindle  
**目标**: 在 Kindle 设备上实现 Rust 阅读器  
**开发环境**: macOS + Nix + ARM 交叉编译  
**目标设备**: Kindle (ARM Linux)  

## 开发环境配置

### 1. 基础环境
```bash
# 操作系统
macOS 14.5.0 (Darwin 24.5.0)

# Shell
/bin/zsh

# 工作目录
/Users/liheng/work/github/koreader/rust-reader
```

### 2. Nix 环境配置
```bash
# 进入 Nix 环境
nix-shell

# 验证环境
echo $IN_NIX_SHELL  # 应该输出非空值
rustc --version     # 验证 Rust 工具链
```

### 3. 项目结构
```
rust-reader/
├── src/
│   ├── main.rs          # 主程序入口
│   ├── framebuffer.rs   # Framebuffer 抽象
│   └── renderer.rs      # 渲染后端
├── Cargo.toml           # 项目配置
├── build-kindle.sh      # 构建脚本
├── ssh-config           # SSH 配置
└── shell.nix           # Nix 环境配置
```

## 完整开发流程

### 阶段1: 基础 Framebuffer 测试

#### 1.1 开发代码
**文件**: `src/main.rs`
**目标**: 测试直接 framebuffer 访问

```rust
// 创建简单的 Hello World 测试
use std::fs::OpenOptions;
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

fn log_message(message: &str) {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    println!("[{}] {}", timestamp, message);
    
    // 写入日志文件
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open("/mnt/us/simple_test.log") {
        let _ = writeln!(file, "[{}] {}", timestamp, message);
    }
}

fn main() {
    log_message("=== 极简 Hello 测试程序 ===");
    // ... 测试代码
}
```

#### 1.2 编译部署
```bash
# 进入 Nix 环境并编译
nix-shell --run "./build-kindle.sh"

# 输出示例:
# 🔨 开始编译 Kindle ARM 版本...
# 📱 目标架构: arm-unknown-linux-musleabihf
# ✅ 编译成功！
# 🚀 自动部署到Kindle设备...
# ✅ 文件传输成功！
# ✅ 权限设置成功！
```

#### 1.3 运行测试
```bash
# SSH 连接到 Kindle 并运行程序
ssh -F ssh-config kindle "cd /mnt/us && ./kindle-reader"

# 输出示例:
# [1752913313] === 极简 Hello 测试程序 ===
# [1752913313] 开始测试...
# [1752913313] ✅ 成功打开 framebuffer
```

#### 1.4 拉取日志分析
```bash
# 拉取日志文件
scp -F ssh-config kindle:/mnt/us/simple_test.log .

# 查看日志内容
cat simple_test.log
```

#### 1.5 问题分析
**发现的问题**:
- Framebuffer 大小为 0 字节
- 所有 ioctl 命令失败
- 屏幕没有变化

**根本原因**: 显示管理器独占 framebuffer 访问

### 阶段2: 显示管理器分析

#### 2.1 系统诊断
```bash
# 检查显示管理器进程
ssh -F ssh-config kindle "ps aux | grep -E '(dmld|Xorg|awesome|blanket)'"

# 检查 framebuffer 使用情况
ssh -F ssh-config kindle "lsof /dev/fb0"

# 检查 E-ink 驱动
ssh -F ssh-config kindle "find /sys -name '*epdc*' -o -name '*eink*'"
```

#### 2.2 关键发现
```
显示管理器栈:
dmld (Display Manager for Linux Devices)
├── Xorg (X11 服务器)
├── awesome (窗口管理器)
└── blanket (屏幕保护程序)

Framebuffer 参数:
- 虚拟大小: 1088x6144 像素
- 步长: 1088 字节
- 计算大小: 6,684,672 字节
```

### 阶段3: X11 环境测试

#### 3.1 开发 X11 测试程序
**文件**: `src/main.rs`
**目标**: 测试 X11 显示环境

```rust
fn main() {
    log_message("=== X11 显示测试 ===");
    
    // 检查 X11 环境
    if let Ok(display) = std::env::var("DISPLAY") {
        log_message(&format!("✅ 发现 X11 显示: {}", display));
    }
    
    // 检查 X11 库
    let x11_libs = [
        "/usr/lib/libX11.so",
        "/usr/lib/libX11.so.6",
    ];
    
    // 尝试运行 X11 程序
    match std::process::Command::new("xset").arg("q").output() {
        Ok(output) => {
            if output.status.success() {
                log_message("✅ X11 服务器响应正常");
            }
        }
        Err(e) => {
            log_message(&format!("❌ 无法查询 X11 服务器: {}", e));
        }
    }
}
```

#### 3.2 编译部署
```bash
# 编译 X11 测试版本
nix-shell --run "./build-kindle.sh"

# 部署到设备
# (自动完成)
```

#### 3.3 运行测试
```bash
ssh -F ssh-config kindle "cd /mnt/us && ./kindle-reader"
```

#### 3.4 日志分析
```bash
# 拉取日志
scp -F ssh-config kindle:/mnt/us/x11_test.log .

# 分析结果
cat x11_test.log
```

#### 3.5 发现的问题
- X11 环境不稳定
- DISPLAY 变量有时设置有时未设置
- X11 服务器响应不稳定

### 阶段4: GTK 环境测试

#### 4.1 修改依赖配置
**文件**: `Cargo.toml`
```toml
[dependencies]
gtk = { version = "0.18", features = ["v3_24"], optional = true }
```

#### 4.2 开发 GTK 测试程序
**文件**: `src/main.rs`
**目标**: 测试 GTK 显示环境

```rust
fn main() {
    log_message("=== GTK Hello World 测试 ===");
    
    // 检查 GTK 环境
    let gtk_libs = [
        "/usr/lib/libgtk-x11-2.0.so.0",
        "/usr/lib/libgtk-x11-2.0.so",
    ];
    
    for lib in &gtk_libs {
        if std::path::Path::new(lib).exists() {
            log_message(&format!("✅ 发现 GTK 库: {}", lib));
        }
    }
    
    // 检查环境变量
    if let Ok(display) = std::env::var("DISPLAY") {
        log_message(&format!("✅ DISPLAY: {}", display));
    } else {
        log_message("❌ DISPLAY 未设置");
    }
    
    #[cfg(feature = "gtk")]
    {
        log_message("✅ GTK 功能已启用");
        // GTK 代码
    }
    
    #[cfg(not(feature = "gtk"))]
    {
        log_message("❌ GTK 功能未启用");
        log_message("请使用 --features gtk 重新编译");
    }
}
```

#### 4.3 编译部署
```bash
# 编译 GTK 测试版本
nix-shell --run "./build-kindle.sh"

# 输出:
# 🔨 开始编译 Kindle ARM 版本...
# 📱 目标架构: arm-unknown-linux-musleabihf
# ✅ 编译成功！
# 📁 输出文件: target/arm-unknown-linux-musleabihf/release/kindle-reader
# 🚀 自动部署到Kindle设备...
# ✅ 文件传输成功！
```

#### 4.4 运行测试
```bash
ssh -F ssh-config kindle "cd /mnt/us && ./kindle-reader"

# 输出:
# [1752929771] === GTK Hello World 测试 ===
# [1752929771] ✅ 发现 GTK 库: /usr/lib/libgtk-x11-2.0.so.0
# [1752929771] ❌ DISPLAY 未设置
# [1752929771] ❌ GTK 功能未启用
```

#### 4.5 日志分析
```bash
# 拉取日志
scp -F ssh-config kindle:/mnt/us/gtk_test.log .

# 分析结果
cat gtk_test.log
```

## 关键发现总结

### 1. 显示环境现状
- ✅ GTK-2.0 库存在且可用
- ✅ Cairo 图形库可用
- ✅ Framebuffer 参数正确 (1088x6144)
- ❌ DISPLAY 环境变量不稳定
- ❌ 显示管理器独占 framebuffer

### 2. 技术挑战
- 显示管理器完全控制显示层
- 直接 framebuffer 访问被覆盖
- X11 环境不稳定
- 需要与现有显示系统协作

### 3. 解决方案
- **方案1**: 使用 GTK 与显示管理器协作
- **方案2**: 使用 Cairo 直接绘制
- **方案3**: 分析 KOReader 实现

## 开发工具和脚本

### 1. 构建脚本
**文件**: `build-kindle.sh`
```bash
#!/bin/bash
set -e

ARM_TARGET="arm-unknown-linux-musleabihf"

# 检查 Nix 环境
if [ -z "$IN_NIX_SHELL" ]; then
    echo "❌ 请先进入Nix环境：nix-shell"
    exit 1
fi

# 编译 ARM 版本
cargo build --release --target $ARM_TARGET --no-default-features --features embedded

# 自动部署
scp -F ssh-config target/$ARM_TARGET/release/kindle-reader kindle:/mnt/us/
ssh -F ssh-config kindle "chmod +x /mnt/us/kindle-reader"
```

### 2. SSH 配置
**文件**: `ssh-config`
```
Host kindle
    HostName 192.168.1.5
    Port 2222
    User root
    StrictHostKeyChecking no
```

### 3. Nix 环境配置
**文件**: `shell.nix`
```nix
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    rustup
    cargo
    rustc
    pkg-config
    openssl
    cmake
  ];
  
  shellHook = ''
    echo "🚀 Kindle阅读器ARM交叉编译环境已准备就绪"
    echo "📱 目标架构: ARM (arm-unknown-linux-musleabihf)"
    echo ""
    echo "✅ 环境配置完成！"
    echo ""
    echo "🔧 可用命令:"
    echo "  ./build-kindle.sh     - 编译ARM版本"
    echo "  cargo build           - 编译本地版本"
    echo "  cargo run book.txt    - 运行本地版本"
  '';
}
```

## 标准开发流程

### 1. 代码开发
```bash
# 1. 进入项目目录
cd /Users/liheng/work/github/koreader/rust-reader

# 2. 编辑源代码
vim src/main.rs

# 3. 本地测试 (可选)
cargo build
cargo run
```

### 2. 编译部署
```bash
# 1. 进入 Nix 环境并编译
nix-shell --run "./build-kindle.sh"

# 2. 验证编译结果
ls -la target/arm-unknown-linux-musleabihf/release/kindle-reader
file target/arm-unknown-linux-musleabihf/release/kindle-reader
```

### 3. 运行测试
```bash
# 1. SSH 连接到 Kindle
ssh -F ssh-config kindle

# 2. 运行程序
cd /mnt/us
./kindle-reader

# 3. 观察输出和屏幕变化
```

### 4. 日志分析
```bash
# 1. 拉取日志文件
scp -F ssh-config kindle:/mnt/us/*.log .

# 2. 分析日志
cat *.log

# 3. 根据日志调整代码
```

### 5. 问题诊断
```bash
# 1. 检查设备状态
ssh -F ssh-config kindle "ps aux | grep -E '(dmld|Xorg|awesome)'"
ssh -F ssh-config kindle "lsof /dev/fb0"
ssh -F ssh-config kindle "cat /sys/class/graphics/fb0/virtual_size"

# 2. 检查环境变量
ssh -F ssh-config kindle "env | grep -E '(DISPLAY|GTK)'"

# 3. 检查库文件
ssh -F ssh-config kindle "ls -la /usr/lib/libgtk*"
```

## 常见问题和解决方案

### 1. 编译问题
**问题**: 编译失败
**解决**: 
```bash
# 确保在 Nix 环境中
nix-shell

# 清理并重新编译
cargo clean
cargo build --release --target arm-unknown-linux-musleabihf
```

### 2. 部署问题
**问题**: SSH 连接失败
**解决**:
```bash
# 检查网络连接
ping 192.168.1.5

# 检查 SSH 配置
cat ssh-config

# 手动连接测试
ssh -F ssh-config kindle "echo 'test'"
```

### 3. 运行问题
**问题**: 程序无法运行
**解决**:
```bash
# 检查文件权限
ssh -F ssh-config kindle "ls -la /mnt/us/kindle-reader"

# 检查依赖
ssh -F ssh-config kindle "ldd /mnt/us/kindle-reader"

# 检查环境
ssh -F ssh-config kindle "env | grep DISPLAY"
```

### 4. 显示问题
**问题**: 屏幕没有变化
**解决**:
```bash
# 检查显示管理器
ssh -F ssh-config kindle "ps aux | grep -E '(Xorg|awesome)'"

# 检查 framebuffer
ssh -F ssh-config kindle "lsof /dev/fb0"

# 检查 E-ink 驱动
ssh -F ssh-config kindle "cat /sys/class/graphics/fb0/blank"
```

## 性能优化建议

### 1. 编译优化
```bash
# 使用发布模式
cargo build --release

# 启用优化
export RUSTFLAGS="-C target-cpu=native"

# 静态链接
cargo build --release --target arm-unknown-linux-musleabihf --no-default-features
```

### 2. 运行时优化
```bash
# 设置环境变量
export DISPLAY=:0.0
export GTK_THEME=Adwaita

# 优化 E-ink 刷新
echo 0 > /sys/class/graphics/fb0/blank
```

## 文档维护

### 1. 更新日志
- 记录每次测试的结果
- 保存关键日志文件
- 记录问题和解决方案

### 2. 代码版本控制
```bash
# 提交代码
git add .
git commit -m "feat: 添加 GTK 显示测试"

# 创建标签
git tag -a v0.1.0 -m "第一个可运行版本"
```

### 3. 文档同步
- 更新 README.md
- 维护开发文档
- 记录 API 变更

---

*文档版本: 1.0*  
*创建时间: 2024-07-19*  
*最后更新: 2024-07-19*  
*作者: Rust Reader 开发团队* 