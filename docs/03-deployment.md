# 部署指南

## 后端必须做的两件事

无论 PHP / Java / 其他任何后端,只需提供 2 个 HTTP 路由:

### 路由 1:渲染页(返回 HTML)

```
GET /
→ HTML(包含 <canvas> 占位 + viewer/pdf-renderer.js)
```

### 路由 2:PDF 文件服务(必须支持 Range)

```
GET /pdf/<name>.pdf
→ 200 OK 或 206 Partial Content
   Content-Type: application/pdf
   Accept-Ranges: bytes
   Content-Range: bytes <start>-<end>/<total>     (只在 206 时)
```

**关键**:必须支持 `Range: bytes=...` header,响应 `206 Partial Content`。

## PHP (Laravel) 实现

```php
// routes/web.php
Route::get('/', fn() => view('viewer', ['pdfUrl' => '/pdf/chuanmei_2026_02.pdf']));

Route::get('/pdf/{name}', function (string $name) {
    $path = public_path("pdf/{$name}");
    if (!file_exists($path)) abort(404);
    return response()->file($path, [
        'Content-Type' => 'application/pdf',
        'Accept-Ranges' => 'bytes',
        'Cache-Control' => 'public, max-age=3600',
    ]);
});
```

`response()->file()` 用的是 Symfony `BinaryFileResponse`,**自带 Range 支持**,直接给 206。

## Java (Spring Boot) 实现

```java
@Controller
public class PdfController {
    @GetMapping(value = "/pdf/{name}", produces = MediaType.APPLICATION_PDF_VALUE)
    public ResponseEntity<Resource> serve(@PathVariable String name) {
        Resource pdf = new ClassPathResource("pdf/" + name);
        if (!pdf.exists()) return ResponseEntity.notFound().build();
        return ResponseEntity.ok()
            .header("Accept-Ranges", "bytes")
            .header("Cache-Control", "public, max-age=3600")
            .body(pdf);
    }
}
```

Spring Boot 的 `ResourceHttpRequestHandler` **自带 Range 支持**,自动响应 206。

## nginx 配置(关键!)

如果用 nginx 反代到 PHP-FPM 或 Spring Boot,**必须关掉 buffering**,否则 Range header 会被吞掉:

```nginx
# /etc/nginx/sites-available/demo
server {
    listen 80;
    server_name 159.203.0.28;

    location /demo-php/ {
        proxy_pass http://localhost:8091/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;

        # ⚠️ 关键:必须关 buffering,否则 Range 不工作
        proxy_buffering off;
        proxy_request_buffering off;
    }

    location /demo-java/ {
        proxy_pass http://localhost:8092/;
        proxy_set_header Host $host;
        proxy_buffering off;
        proxy_request_buffering off;
    }
}
```

## Docker 部署(推荐)

```bash
git clone https://github.com/xiaotianlou/digital-magazine-platform-blueprint
cd digital-magazine-platform-blueprint
docker compose -f deploy/docker-compose.yml up -d
```

启动 2 个容器:
- `php-demo`: Laravel 11 on port 8091
- `java-demo`: Spring Boot 3.4 on port 8092

宿主 nginx 反代到这两个端口。

详细 docker-compose 见 [`deploy/docker-compose.yml`](../deploy/docker-compose.yml)。

## 物理机部署(不用 docker)

### PHP/Laravel
```bash
cd php/
composer install --no-dev --optimize-autoloader
cp .env.example .env
php artisan key:generate
# nginx + PHP-FPM 配置:document_root = php/public/
```

### Java/Spring Boot
```bash
cd java/
mvn clean package -DskipTests
java -jar target/pdfdemo-1.0.0.jar --server.port=8092
```

## 验证部署成功

```bash
# 测 Range 是否生效
curl -s -D - -o /dev/null -H "Range: bytes=0-100" \
  http://your-server/pdf/chuanmei_2026_02.pdf

# 期望:
# HTTP/1.1 206 Partial Content      ← 必须 206
# Accept-Ranges: bytes
# Content-Range: bytes 0-100/62914560
```

浏览器打开 `http://your-server/`:
1. F12 Network 面板,看 `source.pdf` 状态码 = `206`
2. 多次小 Range 请求(每次几十 KB)
3. 不应有任何 jpg 文件请求
4. 滚动:新页 lazy 渲染

## 常见部署问题

| 症状 | 原因 | 解决 |
|---|---|---|
| canvas 一直空白 | Range 请求 200 不是 206 | 检查 nginx `proxy_buffering off` |
| pdf.worker 加载失败 | CSP 拦截 jsdelivr | 加 `Content-Security-Policy: ... cdn.jsdelivr.net` |
| 第一次卡顿 5-10 秒 | 首次拉 PDF.js 库(1.8 MB) | 部署到本地 static 不走 CDN |
| Mobile 渲染慢 | 移动 CPU 弱 | DPR oversample 倍数调小到 1.5(本 demo 默认 2) |
