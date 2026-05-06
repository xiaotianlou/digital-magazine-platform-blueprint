# 部署到服务器

## 159.203.0.28(本 demo 实际部署目标)

```bash
chmod +x setup-on-jobp.sh
./setup-on-jobp.sh
```

完成后:
- http://159.203.0.28/demo-php/
- http://159.203.0.28/demo-java/

## 自定义服务器

修改 `setup-on-jobp.sh` 顶部:
```bash
REMOTE_USER=root
REMOTE_HOST=159.203.0.28
REMOTE_DIR=/opt/magazine-blueprint
SSH_KEY=~/.ssh/server1
```

## 服务器要求

- Docker 24+ (含 docker compose v2)
- nginx(用于反代到 :8091 / :8092)
- 至少 1 GB RAM(Spring Boot ~400 MB,PHP-CLI ~50 MB,Docker overhead ~200 MB)
- 至少 2 GB 磁盘(image + PDF)

## 排错

```bash
# 看容器日志
docker compose -f deploy/docker-compose.yml logs -f

# 看是否真起了
docker ps | grep magazine

# 测 Range 是否工作(关键!不工作就说明 nginx buffering 没关)
curl -s -D - -o /dev/null -H "Range: bytes=0-100" \
  http://localhost:8091/pdf/chuanmei_2026_02.pdf

# 应看到:
# HTTP/1.1 206 Partial Content
# Accept-Ranges: bytes
# Content-Range: bytes 0-100/62914560
```

## nginx 配置要点

`nginx.conf` 关键 3 行:
```nginx
proxy_buffering off;          # ⚠️ 必须关
proxy_request_buffering off;
proxy_http_version 1.1;       # Range 需要 HTTP/1.1
```

如果用 nginx 现成的 `proxy_pass` 不加 buffering 设置,Range header 会被吞掉,206 变 200,PDF.js 拉整 60 MB,慢死。
