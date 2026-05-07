# easy-nginx-ssl    
· Nginx SSL 交互式一键部署脚本，可以快速搭建 HTTPS 反向代理    
· 适用于Debian / Ubuntu 等标准 systemd Linux   
· 支持 Cloudflare Origin Certificate / 非api需手动上传证书    
· 交互式输入 域名 / 本地服务端口 / 证书路径 / 私钥路径   
· 一键生成 Nginx 配置  
· systemd 守护 + 开机自启，掉线自动重启  
· 支持卸载域名配置 / 完全卸载 Nginx    
· 覆盖安装 / 备份旧配置  
· 支持多架构（x86_64 / ARM64）  
```bash
bash <(curl -fSL https://raw.githubusercontent.com/nngt886/easy-nginx-ssl/refs/heads/main/install.sh)
