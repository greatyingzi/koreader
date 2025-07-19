#!/bin/bash

set -e

ARM_TARGET="arm-unknown-linux-musleabihf"

echo "🔨 开始编译 Kindle ARM 版本..."
echo "📱 目标架构: $ARM_TARGET"
echo ""

# 检查是否在Nix环境中
if [ -z "$IN_NIX_SHELL" ]; then
    echo "❌ 请先进入Nix环境："
    echo "   nix-shell"
    exit 1
fi

# 清理之前的构建
echo "🧹 清理之前的构建..."
cargo clean

# 确保ARM目标已安装
echo "📦 检查ARM目标..."
if ! rustup target list --installed | grep -q "$ARM_TARGET"; then
    echo "📦 安装ARM目标..."
    rustup target add $ARM_TARGET
fi

# 编译ARM版本（嵌入式功能）
echo "🔧 编译ARM版本（嵌入式功能）..."
cargo build --release --target $ARM_TARGET --no-default-features --features embedded

# 检查编译结果
if [ -f "target/$ARM_TARGET/release/kindle-reader" ]; then
    echo ""
    echo "✅ 编译成功！"
    echo "📁 输出文件: target/$ARM_TARGET/release/kindle-reader"
    
    # 显示文件信息
    echo ""
    echo "📊 文件信息:"
    ls -lh target/$ARM_TARGET/release/kindle-reader
    
    echo ""
    echo "🔍 文件架构:"
    file target/$ARM_TARGET/release/kindle-reader
    
    echo ""
    echo "📋 部署说明:"
    echo "1. 将文件传输到Kindle设备："
    echo "   scp target/$ARM_TARGET/release/kindle-reader root@kindle:/mnt/us/"
    echo ""
    echo "2. 在Kindle上设置权限："
    echo "   chmod +x /mnt/us/kindle-reader"
    echo "   chmod 666 /dev/fb0 /dev/input/event*"
    echo ""
    echo "3. 运行："
    echo "   ./kindle-reader /mnt/us/documents/book.txt"
    
else
    echo "❌ 编译失败！"
    exit 1
fi 