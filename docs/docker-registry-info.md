# 私有 Docker Registry 信息

## 访问信息

| 项目 | 值 |
|------|------|
| Web UI | https://101.201.37.112:5000/ui/ |
| Registry API | https://101.201.37.112:5000/v2/ |
| 用户名 | admin |
| 密码 | d92RzHUfYgy7Yi9Pop0WUg |

## 证书

- 自签名证书（有效期 10 年）
- SAN 包含 IP：101.201.37.112、172.31.187.89、127.0.0.1
- 证书路径：/opt/docker-registry/certs/domain.crt
- 私钥路径：/opt/docker-registry/certs/domain.key

## 文件结构

```
/opt/docker-registry/
├── docker-compose.yml
├── caddy/Caddyfile
├── auth/htpasswd
├── certs/domain.crt, domain.key
├── data/registry/
└── .admin_password
```

## 客户端使用方法

```bash
# 1. 信任自签名证书（复制证书到客户端）
sudo mkdir -p /etc/docker/certs.d/101.201.37.112:5000
sudo scp root@101.201.37.112:/opt/docker-registry/certs/domain.crt /etc/docker/certs.d/101.201.37.112:5000/ca.crt
sudo systemctl restart docker

# 2. 登录
docker login 101.201.37.112:5000

# 3. 推送镜像
docker tag my-image 101.201.37.112:5000/my-image
docker push 101.201.37.112:5000/my-image

# 4. 拉取镜像
docker pull 101.201.37.112:5000/my-image
```

## 管理命令

```bash
cd /opt/docker-registry

docker compose ps        # 查看服务状态
docker compose logs -f   # 查看日志
docker compose restart   # 重启服务
docker compose down      # 停止服务
docker compose up -d     # 启动服务
```

## 添加用户

```bash
htpasswd -Bbn 用户名 密码 >> /opt/docker-registry/auth/htpasswd
docker compose restart registry
```

## 注意事项

- 阿里云安全组需放行 TCP 端口 5000 入方向
- 浏览器访问 Web UI 时提示证书不受信任，点击「继续访问」即可
- Docker 镜像加速器已配置在 /etc/docker/daemon.json
