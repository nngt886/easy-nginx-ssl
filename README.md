# easy-nginx-ssl    
· Nginx 交互式一键部署脚本，可以快速搭建反向代理    
· 适用于Debian / Ubuntu 等标准 systemd Linux    
· cloudflare SSL 完整（严格）模式   
· Cloudflare 源服务器证书 / 非api方式需粘贴PEM内容   
· cloudflare SSL 灵活模式，不要求证书，适用于无443系端口vps
· 交互式输入 域名 / 本地服务端口 / 证书 / 私钥   
· 一键生成 Nginx 配置  
· systemd 守护 + 开机自启，掉线自动重启  
· 支持卸载域名配置 / 完全卸载 Nginx    
· 覆盖安装 / 备份旧配置  
· 支持多架构（x86_64 / ARM64）  
```bash
bash <(curl -fSL https://raw.githubusercontent.com/nngt886/easy-nginx-ssl/refs/heads/main/install.sh)
