#!/bin/bash

# ======================================
# 🚀 Nginx 自动部署脚本 (优化版)
# ======================================

set -e

echo "======================================"
echo "🚀 Nginx 自动部署脚本（灵活端口 & CF IP 白名单）"
echo "======================================"

# =========================
# Cloudflare IP 列表
# =========================
CF_IPS_URL="https://www.cloudflare.com/ips-v4"
CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

fetch_cf_ips() {
    echo "🌐 正在获取 Cloudflare IP 列表..."
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
        apt update && apt install -y nginx curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release
        yum install -y nginx curl
    else
        echo "❌ 未检测到 apt 或 yum，无法自动安装 Nginx"
        exit 1
    fi
fi

# 检测 systemd 状态
USE_SYSTEMD=0
if systemctl list-units --all | grep -q 'nginx.service'; then
    USE_SYSTEMD=1
fi

# =========================
# 安装 / 配置域名 SSL
# =========================
install_domain() {
    fetch_cf_ips

    echo "[1/5] 基础配置"
    read -p "🌐 域名 (example.com): " DOMAIN

    echo ""
    echo "请选择 SSL 模式："
    echo "1) 完整（严格）SSL —— Cloudflare 到 VPS 全程加密 (HTTPS)"
    echo "2) 灵活 SSL        —— Cloudflare 到 VPS 使用明文 (HTTP)"
    read -p "请输入选项 [1-2]: " SSL_MODE

    # --- 统一询问监听端口 ---
    echo ""
    if [[ "$SSL_MODE" == "1" ]]; then
        echo "ℹ️ 模式：完整（严格）。建议端口: 443, 2053, 2083, 2087, 2096, 8443"
    else
        echo "ℹ️ 模式：灵活。建议端口: 80, 8080, 8880, 2052, 2082, 2086, 2095"
    fi
    read -p "📌 请输入 Nginx 监听端口 (Cloudflare 回源端口): " LISTEN_PORT

    # 验证端口
    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -lt 1 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
        echo "❌ 端口无效"; exit 1
    fi

    SSL_DIR="/etc/nginx/ssl"
    if [[ "$SSL_MODE" == "1" ]]; then
        USE_SSL=1
        mkdir -p "$SSL_DIR"
        echo "📄 请粘贴 SSL 证书 (.crt/.pem)，按 Ctrl+D 保存："
        SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
        cat > "$SSL_CERT"
        echo "🔒 请粘贴 SSL 私钥 (.key)，按 Ctrl+D 保存："
        SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
        cat > "$SSL_KEY"
    else
        USE_SSL=0
    fi

    read -p "⚙️ 本地服务端口 (反代到哪个端口，如 3000): " LOCAL_PORT

    # =========================
    # 生成 Nginx 配置
    # =========================
    NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
    echo "[2/5] 正在生成 Nginx 配置..."

    # 准备 Server 块
    if [[ $USE_SSL -eq 1 ]]; then
        # 完整模式：监听带 ssl
        CONF_HEADER="listen ${LISTEN_PORT} ssl;"
        SSL_STUFF="ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;"
    else
        # 灵活模式：普通监听
        CONF_HEADER="listen ${LISTEN_PORT};"
        SSL_STUFF=""
    fi

    # 写入文件
    cat > "$NGINX_CONF" <<EOF
server {
    ${CONF_HEADER}
    server_name ${DOMAIN};

    ${SSL_STUFF}

    # Cloudflare IP 白名单
EOF
    for ip in $CF_IPS $CF_IPV6S; do
        echo "    allow $ip;" >> "$NGINX_CONF"
    done

    cat >> "$NGINX_CONF" <<EOF
    deny all;

    location / {
        proxy_pass http://127.0.0.1:${LOCAL_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # 如果监听的不是 80，自动加一个 80 重定向到 HTTPS (仅针对完整模式)
    if [[ $USE_SSL -eq 1 && "$LISTEN_PORT" != "80" ]]; then
        cat >> "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF
    fi

    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/
    nginx -t
    
    # 重启服务
    if [[ $USE_SYSTEMD -eq 1 ]]; then
        systemctl restart nginx
    else
        # 兼容自定义服务逻辑
        [[ -f /etc/systemd/system/nginx-custom.service ]] || create_custom_service
        systemctl restart nginx-custom
    fi

    echo "✅ 配置成功！"
    echo "🌐 访问地址: $( [[ $USE_SSL -eq 1 ]] && echo "https" || echo "http" )://${DOMAIN}:${LISTEN_PORT}"
    echo "⚠️  提示：如果端口不是 80/443，请在 CF 后台配置 'Origin Rules' 指向该端口。"
}

# --- 辅助函数：创建自定义服务 ---
create_custom_service() {
    cat > /etc/systemd/system/nginx-custom.service <<EOF
[Unit]
Description=Nginx Custom Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/nginx -g 'daemon off;'
ExecReload=/usr/sbin/nginx -s reload
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable nginx-custom
}

# =========================
# 其他管理功能 (保持原样)
# =========================
uninstall_domain() {
    read -p "请输入要卸载的域名: " DOMAIN
    rm -f "/etc/nginx/sites-available/${DOMAIN}.conf" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
    nginx -s reload
    echo "✅ 已删除。"
}

full_uninstall() {
    echo "正在卸载..."
    apt remove -y nginx || yum remove -y nginx
    echo "✅ 已卸载。"
}

# =========================
# 入口
# =========================
echo "1) 安装/配置  2) 卸载域名  3) 全卸载  4) 退出"
read -p "选择 [1-4]: " ACTION
case $ACTION in
    1) install_domain ;;
    2) uninstall_domain ;;
    3) full_uninstall ;;
    *) exit 0 ;;
esac
