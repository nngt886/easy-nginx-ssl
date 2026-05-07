#!/bin/bash

# ======================================
# 🚀 Nginx 自动部署脚本
# ======================================

set -e

echo "======================================"
echo "🚀 Nginx 自动部署脚本（完整/严格SSL & 灵活SSL + Cloudflare IP 白名单）"
echo "======================================"

# =========================
# Cloudflare IP 列表
# =========================
CF_IPS_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

fetch_cf_ips() {
    CF_IPS=$(curl -s $CF_IPS_URL)
    CF_IPV6S=$(curl -s $CF_IPV6_URL)
}

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
        apt install -y nginx curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y nginx curl
    else
        echo "❌ 未检测到 apt 或 yum，无法自动安装 Nginx"
        exit 1
    fi
fi

# =========================
# 检测系统 nginx.service
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
    fetch_cf_ips

    echo "[1/5] 请输入域名"
    read -p "🌐 域名 (example.com): " DOMAIN

    # Cloudflare Full/Strict 支持端口
    CF_SSL_PORTS="443 2052 2053 2083 2087 2096 8443"

    echo ""
    echo "⚠️ Cloudflare 完整（严格）SSL 支持端口:"
    echo "$CF_SSL_PORTS"
    read -p "📌 VPS 是否能开放以上端口？(y/n): " OPEN_CF_PORTS

    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"

    if [[ "$OPEN_CF_PORTS" =~ ^[Yy]$ ]]; then
        USE_SSL=1
        echo "ℹ️ 选择完整（严格）SSL模式"
        echo "📄 请输入 SSL 证书内容 (PEM 格式)，粘贴完毕 Ctrl+D 保存："
        SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
        cat > "$SSL_CERT"
        echo "✅ 证书文件已生成: $SSL_CERT"

        echo "🔒 请输入 SSL 私钥内容 (PEM 格式)，粘贴完毕 Ctrl+D 保存："
        SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
        cat > "$SSL_KEY"
        echo "✅ 私钥文件已生成: $SSL_KEY"

        echo "ℹ️ 请在 Cloudflare 面板将 SSL 设置为完整（严格）"
    else
        USE_SSL=0
        echo "ℹ️ VPS 端口无法开放完整（严格）SSL，自动使用灵活SSL"
        echo "ℹ️ 请在 Cloudflare 面板将 SSL 设置为灵活"
    fi

    # 再输入本地服务端口
    read -p "⚙️ 本地服务端口 (例如 25551): " LOCAL_PORT

    # =========================
    # 生成 Nginx 配置
    # =========================
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

    echo "[2/5] 正在生成 Nginx 配置..."
    cat > "$NGINX_CONF" <<EOF
# Cloudflare IP 白名单
EOF

    # 添加 IPv4 白名单
    for ip in $CF_IPS; do
        echo "allow $ip;" >> "$NGINX_CONF"
    done
    # 添加 IPv6 白名单
    for ip in $CF_IPV6S; do
        echo "allow $ip;" >> "$NGINX_CONF"
    done
    echo "deny all;" >> "$NGINX_CONF"

    if [[ $USE_SSL -eq 1 ]]; then
        cat >> "$NGINX_CONF" <<EOF
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
    else
        cat >> "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${LOCAL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    fi

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

    echo "[3/5] 检查配置..."
    nginx -t

    # =========================
    # 管理 systemd
    # =========================
    if [[ $USE_SYSTEMD -eq 1 ]]; then
        systemctl restart nginx
        systemctl enable nginx
    else
        echo "[ℹ️] 创建 nginx-custom.service..."
        cat > /etc/systemd/system/nginx-custom.service <<EOF
[Unit]
Description=Nginx 中文 SSL + Cloudflare IP 白名单服务
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

    echo "[4/5] Nginx 配置完成！"
    if [[ $USE_SSL -eq 1 ]]; then
        echo "🌐 https://${DOMAIN} （完整/严格SSL）"
    else
        echo "🌐 http://${DOMAIN} （灵活SSL）"
    fi

    echo "[5/5] 注意：HTTP/HTTPS 端口已限制仅允许 Cloudflare IP 访问，请确保 Cloudflare 面板 SSL 设置与模式匹配"
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
