#!/bin/bash

# ======================================
# 🚀 Nginx SSL 一键部署脚本（终极通用版）
# ======================================

set -e

echo "======================================"
echo "🚀 Nginx SSL 一键部署脚本（终极通用版）"
echo "======================================"

# =========================
# 检测系统是否已安装 Nginx
# =========================
if command -v nginx >/dev/null 2>&1; then
    echo "⚠️ 已安装 Nginx"
    nginx -v
else
    echo "📦 检测到未安装 Nginx，正在安装..."
    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y nginx
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y nginx
    else
        echo "❌ 未检测到 apt 或 yum，无法自动安装 Nginx"
        exit 1
    fi
fi

# =========================
# 检测是否有系统 Nginx 服务
# =========================
if systemctl list-units --all | grep -q 'nginx.service'; then
    USE_SYSTEMD=1
    echo "ℹ️ 使用系统自带 nginx.service"
else
    USE_SYSTEMD=0
    echo "ℹ️ 系统未提供 nginx.service，将创建自定义 nginx-custom.service"
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

    # 创建证书目录
    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"

    # 交互式粘贴证书
    echo "📄 请输入 SSL 证书内容 (PEM 格式)，粘贴完毕后按 Ctrl+D 保存："
    SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
    cat > "$SSL_CERT"
    echo "✅ 证书文件已生成: $SSL_CERT"

    # 交互式粘贴私钥
    echo "🔒 请输入 SSL 私钥内容 (PEM 格式)，粘贴完毕后按 Ctrl+D 保存："
    SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
    cat > "$SSL_KEY"
    echo "✅ 私钥文件已生成: $SSL_KEY"

    # Nginx 配置
    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

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

    echo "[3/4] 检查配置..."
    nginx -t

    # =========================
    # 管理服务
    # =========================
    if [[ $USE_SYSTEMD -eq 1 ]]; then
        systemctl restart nginx
        systemctl enable nginx
    else
        echo "[ℹ️] 创建 nginx-custom.service..."
        cat > /etc/systemd/system/nginx-custom.service <<EOF
[Unit]
Description=Nginx Custom SSL Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -g 'daemon off;'
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
    fi

    echo "[4/4] Nginx SSL 域名配置完成！"
    echo "🌐 https://${DOMAIN}"
}

# =========================
# 卸载单个域名配置
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

    if [[ $USE_SYSTEMD -eq 1 ]]; then
        systemctl restart nginx
    else
        systemctl restart nginx-custom
    fi

    echo "✅ ${DOMAIN} 配置已卸载！"
}

# =========================
# 完全卸载 Nginx
# =========================
full_uninstall() {
    echo "🧹 正在彻底卸载 Nginx..."

    if [[ $USE_SYSTEMD -eq 1 ]]; then
        systemctl stop nginx || true
        systemctl disable nginx || true
    else
        systemctl stop nginx-custom || true
        systemctl disable nginx-custom || true
        [[ -f /etc/systemd/system/nginx-custom.service ]] && rm -v /etc/systemd/system/nginx-custom.service
        systemctl daemon-reload
    fi

    echo "⏳ 删除所有域名配置和证书..."
    rm -vf /etc/nginx/sites-available/*.conf
    rm -vf /etc/nginx/sites-enabled/*.conf
    rm -vf /etc/nginx/ssl/*.crt
    rm -vf /etc/nginx/ssl/*.key

    echo "⏳ 卸载 Nginx 软件包..."
    if command -v apt >/dev/null 2>&1; then
        apt remove -y nginx
        apt autoremove -y
    elif command -v yum >/dev/null 2>&1; then
        yum remove -y nginx
    fi

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
