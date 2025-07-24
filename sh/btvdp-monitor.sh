#!/bin/bash
# 监控目录文件数并自动修改容器环境变量
# 功能：自动安装runlike、清理目录文件、systemd服务管理

### 配置参数 ###
WATCH_DIR_PATTERN="/opt/.airship/storage/disk0/zjhz/btvdp-*/datas"
FILE_THRESHOLD=10  #检测数量大于时会替换下面指定值
STORAGE_NUM=20  #替换成要生成的数量
DIR_SIZE_THRESHOLD=20   # 新增：目录大小阈值（GB）[3](@ref)
CONTAINER_NAME_PREFIX="byte-btvdp_"
SERVICE_NAME="btvdp-monitor"  # systemd服务名称
INSTALL_DIR="/usr/local/bin"  # 脚本安装目录


### 计算目录大小（GB）- 新增函数 ###
get_dir_size_gb() {
    local dir="$1"
    # 使用du计算目录总大小并转换为GB[6,7](@ref)
    local size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    echo $((size_kb / 1024 / 1024))  # KB→MB→GB转换
}
### 自动安装runlike ###
install_runlike() {
    echo "[INSTALL] 正在安装runlike..."
    # 检查pip是否安装
    if ! command -v pip3 >/dev/null && ! command -v pip >/dev/null; then
        echo "[INSTALL] 安装Python pip..."
        if grep -qEi "ubuntu|debian" /etc/os-release; then
            sudo apt update -qq && sudo apt install -y -qq python3-pip
        elif grep -qEi "centos|redhat|rhel" /etc/os-release; then
            sudo yum install -y -q python3-pip
        else
            echo "[ERROR] 不支持的Linux发行版" >&2
            return 1
        fi
    fi

    # 安装runlike
    if sudo python3 -m pip install --no-cache-dir -U runlike; then
        echo "[SUCCESS] runlike安装完成"
        return 0
    fi

    echo "[WARN] pip安装失败，尝试源码安装..."
    if ! command -v git >/dev/null; then
        echo "[INSTALL] 安装git..."
        sudo apt install -y git || sudo yum install -y git
    fi
    
    git clone https://github.com/lavie/runlike.git /tmp/runlike
    cd /tmp/runlike && sudo python3 setup.py install
    cd - >/dev/null
    
    if command -v runlike >/dev/null; then
        echo "[SUCCESS] runlike源码安装成功"
        return 0
    fi
    
    echo "[ERROR] runlike安装失败" >&2
    return 1
}

### 清理目录文件 ###
clean_directory() {
    local dir=$1
    echo "[CLEAN] 清理目录: $dir"
    sudo rm -rf "$dir"/*
    
    # 验证清理结果
    local remaining_files=$(sudo find "$dir" -type f | wc -l)
    if [ "$remaining_files" -eq 0 ]; then
        echo "[SUCCESS] 目录清理完成"
    else
        echo "[WARN] 部分文件未能清理，剩余文件数: $remaining_files"
    fi
}

### 安装systemd服务 ###
install_service() {
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        echo "[ERROR] 请使用sudo运行此命令" >&2
        return 1
    fi

    # 检查服务是否已存在
    if systemctl is-active --quiet "$SERVICE_NAME.service" 2>/dev/null; then
        echo "[INFO] 服务已安装，状态:"
        systemctl status "$SERVICE_NAME.service" --no-pager
        return 0
    fi

    echo "[INSTALL] 正在安装systemd服务..."
    
    # 复制脚本到系统目录
    sudo cp "$0" "$INSTALL_DIR/btvdp_monitor.sh"
    sudo chmod +x "$INSTALL_DIR/btvdp_monitor.sh"

    # 创建service文件
    sudo tee "/etc/systemd/system/$SERVICE_NAME.service" >/dev/null <<EOF
[Unit]
Description=BT VDP Directory Monitor Service
After=docker.service network.target
Requires=docker.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/btvdp_monitor.sh
Restart=always
RestartSec=60
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=$SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME.service"
    sudo systemctl start "$SERVICE_NAME.service"
    
    echo "[SUCCESS] 服务安装完成"
    echo "管理命令:"
    echo "  sudo systemctl start $SERVICE_NAME.service"
    echo "  sudo systemctl stop $SERVICE_NAME.service"
    echo "  sudo systemctl status $SERVICE_NAME.service"
}

### 主监控逻辑 ###
main_monitor() {
    # 获取动态目录
    target_dir=$(ls -d $WATCH_DIR_PATTERN 2>/dev/null | head -n 1)
    if [ -z "$target_dir" ]; then
        echo "[ERROR] 目录不存在: $WATCH_DIR_PATTERN" >&2
        return 1
    fi

    # 提取容器ID
    # 使用正则提取目录中的数字ID
    container_id=$(echo "$target_dir" | grep -oP 'btvdp-\K\d+')
    if [ -z "$container_id" ]; then
        echo "[ERROR] 无法从路径提取容器ID: $target_dir" >&2
        return 1
    fi
   
    container_name="${CONTAINER_NAME_PREFIX}${container_id}"
    echo "[INFO] 监控目录: $target_dir | 目标容器: $container_name"
    echo "[INFO] 监控阈值: 文件数 ≥ $FILE_THRESHOLD 且 目录大小 > ${DIR_SIZE_THRESHOLD}GB"  # 新增提示

    # 检查runlike
    if ! command -v runlike >/dev/null; then
        install_runlike || return 1
    fi

    # 监控循环
    while true; do
        file_count=$(find "$target_dir" -type f | wc -l)
        echo "$(date +'%F %T') 当前文件数: $file_count (阈值: $FILE_THRESHOLD)"
        
        dir_size_gb=$(get_dir_size_gb "$target_dir")  # 新增：获取目录大小

        # 打印监控状态（新增目录大小显示）
        echo "$(date +'%F %T') 文件数: $file_count/$FILE_THRESHOLD | 目录大小: ${dir_size_gb}GB/${DIR_SIZE_THRESHOLD}GB"

       # if [ "$file_count" -ge "$FILE_THRESHOLD" ]; then
        if [ "$file_count" -ge "$FILE_THRESHOLD" ] && [ "$dir_size_gb" -gt "$DIR_SIZE_THRESHOLD" ]; then
            echo "[!] 文件数超过阈值，准备修改容器环境变量..."
            
            # 清理目录文件
            clean_directory "$target_dir"
            
            # 获取并修改启动命令
            original_cmd=$(runlike $container_name)
            new_cmd=$(echo "$original_cmd" | \
                sed "s|/storage:45|/storage:${STORAGE_NUM}|g")

            
		 echo "[DEBUG] 修改后命令: $new_cmd"  # 增加此行查看最终命令
            # 重启容器
            docker stop $container_name
            docker rm $container_name
            eval $new_cmd

            echo "[SUCCESS] 容器已重启，新环境变量生效: PI_MOUNT_PATH=/storage:6:"
            # 不退出，继续监控
        fi
        sleep 60
    done
}

### 主入口 ###
case "$1" in
    --install-service)
        install_service
        ;;
    *)
        main_monitor
        ;;
esac
