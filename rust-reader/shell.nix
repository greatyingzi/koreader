{ pkgs ? import <nixpkgs> {} }:

let
  # 使用 musl 静态链接版本，更适合嵌入式设备
  armTarget = "arm-unknown-linux-musleabihf";
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    # 基础工具
    rustup
    pkg-config
    git
    
    # 交叉编译工具链
    pkgsCross.armv7l-hf-multiplatform.stdenv.cc
    pkgsCross.armv7l-hf-multiplatform.buildPackages.binutils
    
    # SDL2依赖（用于桌面测试）
    SDL2
    SDL2_image
    SDL2_mixer
    SDL2_ttf
  ];

  # 设置环境变量
  shellHook = ''
    echo "🚀 Kindle阅读器ARM交叉编译环境已准备就绪"
    echo "📱 目标架构: ARM (${armTarget})"
    echo ""
    
    # 添加交叉编译器到PATH
    export PATH="${pkgs.pkgsCross.armv7l-hf-multiplatform.stdenv.cc}/bin:$PATH"
    
    # 设置Rust交叉编译环境变量
    export CARGO_TARGET_ARM_UNKNOWN_LINUX_MUSLEABIHF_LINKER=armv7l-unknown-linux-gnueabihf-gcc
    export CC_arm_unknown_linux_musleabihf=armv7l-unknown-linux-gnueabihf-gcc
    export CXX_arm_unknown_linux_musleabihf=armv7l-unknown-linux-gnueabihf-g++
    export AR_arm_unknown_linux_musleabihf=armv7l-unknown-linux-gnueabihf-ar
    
    # 确保Rust工具链可用
    if ! command -v rustc &> /dev/null; then
        echo "❌ 请先安装Rust工具链："
        echo "   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
        exit 1
    fi
    
    # 添加ARM目标
    if ! rustup target list --installed | grep -q "${armTarget}"; then
      echo "📦 正在安装ARM目标..."
      rustup target add ${armTarget}
    fi
    
    echo "✅ 环境配置完成！"
    echo ""
    echo "🔧 可用命令:"
    echo "  ./build-kindle.sh     - 编译ARM版本"
    echo "  cargo build           - 编译本地版本"
    echo "  cargo run book.txt    - 运行本地版本"
    echo ""
  '';

  # 设置PKG_CONFIG路径
  PKG_CONFIG_PATH = "${pkgs.SDL2.dev}/lib/pkgconfig:${pkgs.SDL2_image}/lib/pkgconfig";
} 