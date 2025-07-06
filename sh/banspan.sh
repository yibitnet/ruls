#!/bin/bash

# 脚本功能：禁用邮件服务端口 + 修改SSH端口为6292 + 添加CPU监控上报
# 注意：执行前请确保你有root权限或sudo访问
#!/bin/bash

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用sudo运行此脚本"
  exit 1
fi

# 检查当前IPv6状态
ipv6_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
if [ "$ipv6_status" -eq 0 ]; then
  echo "检测到IPv6已启用 (disable_ipv6=0)，正在禁用..."
  
  # === IPv6禁用操作开始 ===
  # 创建配置文件备份
  echo "创建配置文件备份: /etc/sysctl.conf.bak"
  cp /etc/sysctl.conf /etc/sysctl.conf.bak
  
  # 清理现有配置
  echo "清理现有IPv6配置..."
  sed -i '/net.ipv6.conf.\.disable_ipv6/d' /etc/sysctl.conf
  
  # 添加新的禁用配置
  echo "添加新的IPv6禁用配置..."
  cat >> /etc/sysctl.conf << EOF

# IPv6禁用配置 (由脚本添加)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  
  # 应用配置
  echo "应用新配置..."
  sysctl -p
  
  # 验证结果
  new_status=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6)
  if [ "$new_status" -eq 1 ]; then
    echo "IPv6 已成功禁用"
  else
    echo "警告: IPv6 禁用可能未完全生效"
  fi
  # === IPv6禁用操作结束 ===
elif [ "$ipv6_status" -eq 1 ]; then
  echo "IPv6 已禁用，无需操作"
else
  echo "未知的IPv6状态: $ipv6_status"
  exit 1
fi

# 邮件服务端口列表（SMTP/POP3/IMAP）
MAIL_PORTS=(25 465 587 110 995 143 993)

# 安装必要的工具
if ! command -v curl &> /dev/null; then
    sudo apt update
    sudo apt install -y curl
fi

# 安装iptables（如果未安装）
if ! command -v iptables &> /dev/null; then
    sudo apt install -y iptables
fi

# 备份当前iptables规则
sudo iptables-save > ~/iptables_backup_$(date +%F).rules

# 禁用邮件服务端口（入站+出站）
for port in "${MAIL_PORTS[@]}"; do
    sudo iptables -A INPUT -p tcp --dport $port -j DROP
    sudo iptables -A INPUT -p udp --dport $port -j DROP
    sudo iptables -A OUTPUT -p tcp --dport $port -j DROP
    sudo iptables -A OUTPUT -p udp --dport $port -j DROP
done

# 预先设置iptables-persistent的配置
echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" | sudo debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | sudo debconf-set-selections

# 安装iptables-persistent（无交互）
sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent

# 保存iptables规则（持久化）
sudo netfilter-persistent save

# 修改SSH端口
sudo sed -i '/^#*Port .*/d' /etc/ssh/sshd_config
echo "Port 6292" | sudo tee -a /etc/ssh/sshd_config

# 允许新SSH端口的防火墙
sudo iptables -A INPUT -p tcp --dport 6292 -j ACCEPT

# 重启SSH服务
sudo systemctl restart ssh

# ================= 添加CPU监控上报功能 =================

# 创建监控脚本
sudo tee /usr/local/bin/cpu_monitor.sh > /dev/null <<'EOF'
#!/bin/bash

# CPU监控脚本 - 每30分钟运行一次
REPORT_URL="http://server.yibit.net/report.php"
HOSTNAME=$(hostname)
TIMESTAMP=$(date +"%Y-%m-%d %T")

# 获取CPU使用率超过90%的进程
HIGH_CPU_PROCESSES=$(ps -eo pid,user,%cpu,cmd --sort=-%cpu | awk 'NR>1 && $3 > 90')

if [ -n "$HIGH_CPU_PROCESSES" ]; then
    # 构建JSON数据
    JSON_DATA="{\"hostname\":\"$HOSTNAME\",\"timestamp\":\"$TIMESTAMP\",\"processes\":["
    
    while IFS= read -r line; do
        PID=$(echo "$line" | awk '{print $1}')
        USER=$(echo "$line" | awk '{print $2}')
        CPU=$(echo "$line" | awk '{print $3}')
        CMD=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf $i" "; print ""}' | sed 's/"/\\"/g')
        
        JSON_DATA+="{\"pid\":$PID,\"user\":\"$USER\",\"cpu\":$CPU,\"command\":\"$CMD\"},"
    done <<< "$HIGH_CPU_PROCESSES"
    
    JSON_DATA=${JSON_DATA%,} # 移除最后一个逗号
    JSON_DATA+="]}"
    
    # 发送HTTP请求
    curl -X POST -H "Content-Type: application/json" -d "$JSON_DATA" "$REPORT_URL" > /dev/null 2>&1
fi
EOF

# 设置执行权限
sudo chmod +x /usr/local/bin/cpu_monitor.sh

# 创建定时任务
CRON_JOB="*/30 * * * * root /usr/local/bin/cpu_monitor.sh"
if ! grep -q "/usr/local/bin/cpu_monitor.sh" /etc/crontab; then
    echo "$CRON_JOB" | sudo tee -a /etc/crontab > /dev/null
fi

# 确保cron服务运行
sudo systemctl restart cron

# 输出状态信息
echo "配置完成！"
echo "----------------------------------------"
echo "已禁用邮件端口: ${MAIL_PORTS[*]}"
echo "SSH端口已修改为: 6292"
echo "已添加CPU监控任务，每30分钟上报高CPU进程"
echo "----------------------------------------"
echo "重要提示："
echo "1. 请使用新端口6292连接SSH"
echo "2. 旧SSH端口(22)已自动失效"
echo "3. iptables规则备份在: ~/iptables_backup_*.rules"
echo "4. CPU监控脚本位置: /usr/local/bin/cpu_monitor.sh"
