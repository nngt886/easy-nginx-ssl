#!/bin/bash

# ======================================
# 🚀 Nginx SSL 一键部署脚本（升级版）
# 💡 特点：
# - 交互式输入域名、证书路径、私钥路径、本地端口
# - 自动生成 Nginx 配置
# - 支持卸载 / 覆盖安装 / 备份旧配置
# - systemd 守护 + 开机自启
# ======================================

set -e

echo "======================================"
echo "🚀 Nginx SSL 一键部署脚本（升级版）"
echo "======================================"

# 👉 检测是否已安装 Nginx
if ! command -v nginx >/dev/null 2>&1; then
    echo "📦 检测到未安装 Nginx，正在安装..."
    apt update
    apt install -y nginx
else
    echo "⚠️ 检测到已安装 Nginx"
    nginx -v
fi

# ======================================
# [1] 输入用户配置
# ======================================
echo ""
echo "[1/4] 请输入你的配置信息"

read -p "🌐 域名 (example.com): " DOMAIN
read -p "⚙️ 本地服务端口 (例如 8000): " LOCAL_PORT
read -p "📄 证书路径 (PEM/CRT): " SSL_CERT
read -p "🔒 私钥路径 (KEY): " SSL_KEY

# 检查文件是否存在
if [[ ! -f "$SSL_CERT" ]]; then
    echo "❌ 证书文件不存在: $SSL_CERT"
    exit 1
fi
if [[ ! -f "$SSL_KEY" ]]; then
    echo "❌ 私钥文件不存在: $SSL_KEY"
    exit 1
fi

NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"

# ======================================
# [2] 检查已有配置
# ======================================
if [[ -f "$NGINX_CONF" ]]; then
    echo ""
    echo "⚠️ 检测到已有配置文件: $NGINX_CONF"
    echo "请选择操作："
    echo "1) 覆盖旧配置"
    echo "2) 备份旧配置再安装"
    echo "3) 卸载该域名配置"
    echo "4) 退出"

    read -p "请输入选项: " EXIST_ACTION

    case "$EXIST_ACTION" in
        1)
            echo "🔄 将覆盖旧配置..."
            ;;
        2)
            BACKUP_CONF="${NGINX_CONF}.$(date +%Y%m%d%H%M%S).bak"
            cp "$NGINX_CONF" "$BACKUP_CONF"
            echo "📦 已备份旧配置到: $BACKUP_CONF"
            ;;
        3)
            echo "🧹 卸载域名配置..."
            rm -f "$NGINX_CONF"
            rm -f "/etc/nginx/sites-enabled/${DOMAIN}.conf"
            systemctl restart nginx-custom
            echo "✅ 卸载完成"
            exit 0
            ;;
        4)
            echo "👋 已退出"
            exit 0
            ;;
        *)
            echo "❌ 无效选项"
            exit 1
            ;;
    esac
fi

echo ""
echo "📌 配置如下："
echo "👉 域名: $DOMAIN"
echo "👉 本地端口: $LOCAL_PORT"
echo "👉 证书: $SSL_CERT"
echo "👉 私钥: $SSL_KEY"

# ======================================
# [3] 生成 Nginx 配置
# ======================================
echo ""
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

# 启用站点
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/

# 测试 Nginx 配置
nginx -t

echo "✅ Nginx 配置生成完成"

# ======================================
# [4] systemd 守护 + 开机自启
# ======================================
echo ""
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

echo "✅ systemd 配置完成"

# ======================================
# [5] 启动服务 & 完成提示
# ======================================
echo ""
echo "[4/4] 启动 Nginx 服务..."
systemctl restart nginx-custom

echo "======================================"
echo "🎉 部署完成！"
echo ""
echo "📌 访问方式： https://${DOMAIN}"
echo "📌 常用命令："
echo "👉 状态: systemctl status nginx-custom"
echo "👉 日志: journalctl -u nginx-custom -f"
echo "👉 重启: systemctl restart nginx-custom"
echo "👉 卸载: 重新运行脚本选择卸载即可"
echo "======================================"
