#!/bin/bash

# 定义目标目录和下载URL
TARGET_DIR="/root/limit"
DOWNLOAD_URL="http://101.32.108.68:856/docker/env.zip"

# 创建目标目录（如果不存在）
mkdir -p "$TARGET_DIR" || {
    echo "错误：无法创建目录 $TARGET_DIR"
    exit 1
}

# 进入目标目录
cd "$TARGET_DIR" || {
    echo "错误：无法进入目录 $TARGET_DIR"
    exit 1
}

# 检查并安装必要工具
if ! command -v unzip &> /dev/null; then
    echo "检测到未安装unzip，正在自动安装..."
    sudo apt update && sudo apt install -y unzip || {
        echo "错误：unzip安装失败"
        exit 1
    }
fi

# 下载文件
echo "正在下载环境包..."
wget -q --show-progress "$DOWNLOAD_URL" || {
    echo "错误：文件下载失败"
    exit 1
}

# 解压文件
echo "正在解压文件..."
unzip -o env.zip || {
    echo "错误：解压失败"
    exit 1
}

# 清理压缩包
rm -f env.zip

# 检查脚本是否存在
if [ ! -f manage_docker_proxy.sh ]; then
    echo "错误：解压后未找到 manage_docker_proxy.sh"
    exit 1
fi

# 添加执行权限
chmod +x manage_docker_proxy.sh || {
    echo "警告：权限设置失败，尝试继续执行"
}

# 执行安装命令
echo "正在执行安装..."
./manage_docker_proxy.sh install || {
    echo "错误：安装命令执行失败"
    exit 1
}

# 执行启动命令
echo "正在启动服务..."
./manage_docker_proxy.sh start || {
    echo "错误：启动命令执行失败"
    exit 1
}

echo "✅ 所有操作已完成！"
echo "文件位置：$TARGET_DIR"
