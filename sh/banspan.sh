#!/bin/bash

# 脚本功能：禁用邮件服务端口 + 修改SSH端口为6292
# 注意：执行前请确保你有root权限或sudo访问

# 邮件服务端口列表（SMTP/POP3/IMAP）
MAIL_PORTS=(25 465 587 110 995 143 993)

# 安装iptables（如果未安装）
if ! command -v iptables &> /dev/null; then
    sudo apt update
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

# 预先设置iptables-persistent的配置（关键修改）
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

# 输出状态信息
echo "配置完成！"
echo "----------------------------------------"
echo "已禁用邮件端口: ${MAIL_PORTS[*]}"
echo "SSH端口已修改为: 6292"
echo "当前防火墙规则:"
sudo iptables -L -n --line-numbers | grep -E "6292|${MAIL_PORTS[0]}"
echo "----------------------------------------"
echo "重要提示："
echo "1. 请使用新端口6292连接SSH"
echo "2. 旧SSH端口(22)已自动失效"
echo "3. iptables规则备份在: ~/iptables_backup_*.rules"
