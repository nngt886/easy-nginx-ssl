install_domain() {
    echo "[1/4] 请输入域名和相关信息"
    read -p "🌐 域名 (example.com): " DOMAIN
    read -p "⚙️ 本地服务端口 (例如 8000): " LOCAL_PORT

    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"

    # 输入证书内容
    echo "📄 请输入 SSL 证书内容 (PEM 格式)，粘贴完直接回车即可："
    read -r -p "" SSL_CERT_CONTENT
    SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
    echo "$SSL_CERT_CONTENT" > "$SSL_CERT"
    echo "✅ 证书文件已生成: $SSL_CERT"

    # 输入私钥内容
    echo "🔒 请输入私钥内容 (PEM 格式)，粘贴完直接回车即可："
    read -r -p "" SSL_KEY_CONTENT
    SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
    echo "$SSL_KEY_CONTENT" > "$SSL_KEY"
    echo "✅ 私钥文件已生成: $SSL_KEY"

    # 后续 Nginx 配置保持原样
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
