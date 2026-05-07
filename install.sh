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

    echo ""
    echo "请选择 SSL 模式："
    echo "1) 完整（严格）SSL —— Cloudflare 到 VPS 全程加密，需要 VPS 配置证书"
    echo "2) 灵活 SSL        —— Cloudflare 到 VPS 使用 HTTP，VPS 无需证书"
    read -p "请输入选项 [1-2]: " SSL_MODE

    SSL_DIR="/etc/nginx/ssl"
    mkdir -p "$SSL_DIR"

    if [[ "$SSL_MODE" == "1" ]]; then
        USE_SSL=1
        echo ""
        echo "ℹ️ Cloudflare 完整（严格）SSL 回源支持的常用端口:"
        echo "   443  2053  2083  2087  2096  8443"
        echo "   也可使用其他任意端口，配合 Cloudflare Origin Rules 回源即可"
        echo ""
        read -p "📌 请输入 Nginx 监听端口（即 Cloudflare 回源端口，例如 443、8443、55555）: " LISTEN_PORT

        # 验证端口范围
        if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -lt 1 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
            echo "❌ 端口无效，必须为 1-65535 之间的数字"
            exit 1
        fi

        echo "📄 请输入 SSL 证书内容 (PEM 格式)，粘贴完毕 Ctrl+D 保存："
        SSL_CERT="${SSL_DIR}/${DOMAIN}.crt"
        cat > "$SSL_CERT"
        echo "✅ 证书文件已生成: $SSL_CERT"

        echo "🔒 请输入 SSL 私钥内容 (PEM 格式)，粘贴完毕 Ctrl+D 保存："
        SSL_KEY="${SSL_DIR}/${DOMAIN}.key"
        cat > "$SSL_KEY"
        echo "✅ 私钥文件已生成: $SSL_KEY"

        echo "ℹ️ 请在 Cloudflare 面板将 SSL 设置为完整（严格）"
        if [ "$LISTEN_PORT" != "443" ]; then
            echo "ℹ️ 由于监听端口非 443，请在 Cloudflare 面板配置 Origin Rules，将回源端口设置为 ${LISTEN_PORT}"
        fi
    else
        USE_SSL=0
