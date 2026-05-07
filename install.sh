#!/bin/bash

# ======================================
# 🚀 Nginx SSL 一键部署脚本（升级版）
# 💡 特点：
# - 交互式输入域名、证书路径、私钥路径、本地端口
# - 自动生成 Nginx 配置
# - 支持卸载域名配置 / 完全卸载 Nginx
# - 覆盖安装 / 备份旧配置
# - systemd 守护 + 开机自启
# ======================================

set -e

echo "======================================"
echo "🚀 Nginx SSL 一键部署脚本（升级版）"
echo "======================================"

# =========================
# 检测是否已安装 Nginx
# =========================
if command -v nginx >/dev/null 2>&1; then
    echo "⚠️ 已安装 Nginx"
    nginx -v
    # 显示已配置的域名和端口
    echo "📌 已存在配置的域名和端口："
    for f in /etc/nginx/sites-available/*.conf; do
        [[ -f "$f" ]] || continue
        DOMAIN=$(grep -m1 'server_name' "$f" | awk '{print $2}' | tr -d ';')
        PORT=$(grep -m1 'proxy_pass' "$f" | awk -F':' '{print $NF}' | tr -d ';')
        echo "   🌐 $DOMAIN -> 本地端口: $PORT"
    done
else
    echo "📦 检测到未安装 Nginx，正在安装..."
    apt update
    apt install -y nginx
fi

# =========================
# 用户操作选择
# =========================
echo ""
echo "请选择操作："
echo "1) 安装 / 配置域名 SSL"
echo "2) 卸载某个域名配置"
echo "3) 完全卸载 Nginx"
echo "4) 退出"
read -p "请输入选项 [1-4]: " ACTION

# =========================
# 安装 / 配置域名 SSL
# =========================
install_domain() {
    echo "[1/4] 请输入域名和相关信息"
    read -p "🌐 域名 (example.com): " DOMAIN
    read -p "⚙️ 本地服务端口 (例如 8000): " LOCAL_PORT
    read -p "📄 证书路径 (PEM/CRT): " SSL_CERT
    read -p "🔒 私钥路径 (KEY): " SSL_KEY

    # 检查文件是否存在
    [[ -f "$SSL_CERT" ]] || { echo "❌ 证书文件不存在: $SSL_CERT"; exit 1; }
    [[ -f "$SSL_KEY" ]] || { echo "❌ 私钥文件不存在: $SSL_KEY"; exit 1; }

    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

    # 检查已有配置
    if [[ -f "$NGINX_CONF" ]]; then
        echo "⚠️ 已存在配置文件: $NGINX_CONF"
        echo "请选择操作："
        echo "1) 覆盖旧配置"
        echo "2) 备份旧配置再安装"
        echo "3) 退出"
        read -p "请输入选项: " EXIST_ACTION
        case "$EXIST_ACTION" in
            1) echo "🔄 覆盖旧配置..." ;;
            2)
                BACKUP_CONF="${NGINX_CONF}.$(date +%Y%m%d%H%M%S).bak"
                cp "$NGINX_CONF" "$BACKUP_CONF"
                echo "📦 已备份旧配置到: $BACKUP_CONF"
                ;;
            3) echo "👋 已退出"; exit 0 ;;
            *) echo "❌ 无效选项"; exit 1 ;;
        esac
    fi

    echo "[2/4] 正在生成 Nginx 配置..."
    cat > "$NGINX_CONF" <<EOF
server {
    listen 443 ssl;
    server_name ${DOMAIN};

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://127.0.0.1:${LOCAL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

    nginx -t

    echo "[3/4] 创建 systemd 服务..."
    cat > /etc/systemd/system/nginx-custom.service <<EOF
[Unit]
Description=Nginx Custom SSL Service
After=network.target

[Service]
Type=forking
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/usr/sbin/nginx -s quit
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx-custom
    systemctl restart nginx-custom

    echo "[4/4] Nginx SSL 域名配置完成！"
    echo "🌐 https://${DOMAIN}"
}

# =========================
# 卸载某个域名配置
# =========================
uninstall_domain() {
    read -p "请输入要卸载的域名: " DOMAIN
    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

    if [[ ! -f "$NGINX_CONF" ]]; then
        echo "❌ 配置文件不存在: $NGINX_CONF"; exit 1
    fi

    echo "🧹 卸载域名配置..."
    rm -v "$NGINX_CONF"
    rm -v "/etc/nginx/sites-enabled/${DOMAIN}.conf"
    systemctl restart nginx-custom
    echo "✅ ${DOMAIN} 配置已卸载！"
}

# =========================
# 完全卸载 Nginx
# =========================
full_uninstall() {
    echo "🧹 正在彻底卸载 Nginx..."
    echo "⏳ 停止 Nginx 服务..."
    systemctl stop nginx-custom 2>/dev/null || true
    echo "⏳ 禁用开机自启..."
    systemctl disable nginx-custom 2>/dev/null || true

    echo "⏳ 删除所有域名配置..."
    rm -vf /etc/nginx/sites-available/*.conf
    rm -vf /etc/nginx/sites-enabled/*.conf

    if [[ -f /etc/systemd/system/nginx-custom.service ]]; then
        echo "⏳ 删除 systemd 服务文件..."
        rm -v /etc/systemd/system/nginx-custom.service
    fi

    echo "⏳ 卸载 Nginx 软件包..."
    apt remove -y nginx
    apt autoremove -y

    echo "⏳ 重新加载 systemd..."
    systemctl daemon-reexec

    echo "✅ Nginx 已完全卸载！"
}

# =========================
# 执行用户选择
# =========================
case $ACTION in
    1) install_domain ;;
    2) uninstall_domain ;;
    3) full_uninstall ;;
    4) echo "👋 已退出"; exit 0 ;;
    *) echo "❌ 无效选项"; exit 1 ;;
esac
