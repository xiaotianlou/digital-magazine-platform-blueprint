# 工程坑记录(部署本 demo 时实际踩过的)

> 同事照着部署时大概率会撞同样的坑,先看这页省 1-2 天调试。

## 1. PHP `pdo_sqlite` 扩展装不上 — Alpine 没自带 sqlite-dev

**症状**:`docker build` 在 `docker-php-ext-install zip pdo_sqlite` 步报错:
```
configure: error: Package requirements (sqlite3 >= 3.7.7) were not met:
Package 'sqlite3' not found
```

**根因**:Alpine `php:8.3-cli-alpine` base image 不带 sqlite 库。

**解决**:demo 不需要数据库,把 `pdo_sqlite` 从 Dockerfile 删了:
```dockerfile
RUN docker-php-ext-install zip   # 不再装 pdo_sqlite
```

如果你的项目真需要 sqlite,加 `apk add --no-cache sqlite-dev` 即可。

---

## 2. **`php artisan serve` 不支持 HTTP Range header** ⚠️ 核心坑

**症状**:本来想用最简洁的 Laravel 内置 dev server `php artisan serve`,
所有路由都正常,但 PDF Range request 返回 200 而非 206:
```bash
curl -D - -o /dev/null -H "Range: bytes=0-100" http://localhost:8091/pdf/x.pdf
# HTTP/1.1 200 OK
# Content-Length: 61771678   ← 全部内容,Range 被吞了
```

PDF.js 只能拉整个 60 MB,延迟巨大,**用户体验等同于直接下整本 PDF**。

**根因**:[PHP bug #68057](https://bugs.php.net/bug.php?id=68057),PHP CLI 内置 dev server 从 2014 年至今都不实现 Range / Partial Content。

**解决**:**生产就不能用 `php artisan serve`**,必须 nginx + php-fpm。本 repo 的 Dockerfile 就是这么做的(supervisord 同进程跑 nginx + php-fpm)。

**验证**:
```bash
curl -D - -o /dev/null -H "Range: bytes=0-100" http://localhost:8091/pdf/x.pdf
# HTTP/1.1 206 Partial Content    ← 必须 206,不然 PDF.js 拉全文
# Content-Range: bytes 0-100/61771678
```

**教训**:**Laravel 应用部署 PDF 矢量渲染,本地开发也最好用 `nginx-test` 容器或 Valet,别用 artisan serve**。

---

## 3. Spring Boot static 资源默认映射到根 `/` 不是 `/static/`

**症状**:Java 容器 `/static/pdf-renderer.js` 返回 404。

**根因**:Spring Boot 的 `spring.web.resources.static-locations` 默认是 `classpath:/static/`,但 URL 路径映射是**根**,即 `src/main/resources/static/pdf-renderer.js` → 浏览器访问 `/pdf-renderer.js`(没有 `/static/` 前缀)。

PHP/Laravel 不一样:`public/static/x.js` → `/static/x.js`,前缀保留。

**解决**:Java 模板里别加 `/static/` 前缀:
```html
<!-- ❌ 错(Spring Boot)-->
<script src="/static/pdf-renderer.js"></script>

<!-- ✅ 对 -->
<script src="/pdf-renderer.js"></script>
```

或者改 `application.yml`:
```yaml
spring:
  web:
    resources:
      static-locations: classpath:/static/
      add-mappings: true
spring:
  mvc:
    static-path-pattern: /static/**   # 强制加前缀
```

但通常不改配置,让 Spring 走默认即可。

---

## 4. 服务器没装 nginx — 直接 docker expose 端口

**症状**:`setup-on-jobp.sh` 想往 `/etc/nginx/sites-available/` cp 配置文件,
但服务器 nginx 不存在(我们的 159.203.0.28 现有 viewer 直接 uvicorn 跑 :8090,没经过 nginx)。

**解决**:
- 选项 A:容器直接 expose 主机端口(本 demo 用这个,8091/8092)
- 选项 B:`apt install nginx` 然后部署 nginx 配置(适合多个 service 共享 80 端口)

如果同事服务器有 nginx,他们应该用 **B**(更优雅)— `deploy/nginx.conf` 已经写好了反代 `proxy_buffering off` 的配置。

---

## 5. **Mac 清晰、Windows 模糊** — DPR 跨平台坑

**症状**:Mac retina 屏看 PDF.js canvas 渲染极清晰,Windows 普通屏明显糊。

**根因**:Mac `devicePixelRatio = 2`,Windows 普通屏 `= 1`。
如果代码写:
```javascript
const scale = targetWidth / pdfWidth;        // ❌ 不考虑 DPR
canvas.width = pdfPageWidth * scale;
```
Mac 渲染分辨率 2x,Windows 1x — 物理像素差一半。

**解决**(本 demo 已实现):
```javascript
const dpr = Math.max(window.devicePixelRatio || 1, 2);  // 强制下限 2
const scale = (targetWidth / pdfWidth) * dpr * 2;       // × 2 oversample
canvas.width = pdfPageWidth * scale;        // 物理像素
canvas.style.width = targetWidth + 'px';    // CSS 像素
```

`Math.max(DPR, 2)` 让 Windows 也按 retina 标准渲染,canvas 物理像素增加 4 倍,
弥补硬件密度差。

**代价**:每个 canvas 内存翻倍(~32 MB → 64 MB),但 IntersectionObserver 限制
在视口 500px 内才渲染,常驻内存仍可控。

---

## 6. nginx 反代 Range 必须关 buffering

**症状**(可能撞):同事项目装了 nginx 反代到 PHP-FPM/Spring Boot,
后端真的输出了 206,但浏览器收到的还是 200。

**根因**:nginx 默认开 `proxy_buffering on`,会**先把整个上游响应缓冲再吐给前端**,Range 失效。

**解决**:`nginx.conf` 加:
```nginx
location /demo/ {
    proxy_pass http://localhost:8091/;
    proxy_buffering off;          # ⚠️ 必须关
    proxy_request_buffering off;
}
```

本 demo 没用 nginx 反代(直接 expose 端口),所以本身没踩这坑,但**同事生产部署多半要踩**,文档先警告。

---

## 7. Git 提交 60 MB PDF — GitHub 警告但允许

**症状**:`git push` 时 GitHub 输出:
```
remote: warning: File chuanmei_2026_02.pdf is 58.91 MB; this is larger
than GitHub's recommended maximum file size of 50.00 MB
```

**说明**:GitHub **建议** < 50 MB,**硬上限** 100 MB / 文件。本 demo 的 PDF 在中间,push 成功但带 warning。

**正经做法**(同事项目):用 [Git LFS](https://git-lfs.com):
```bash
git lfs install
git lfs track "*.pdf"
git add .gitattributes
git add path/to/big.pdf
git commit -m "Add demo PDF via LFS"
```

LFS 的好处:大文件不进 git history,clone 速度快;坏处:有 quota(免费 1 GB)。

或者:**完全不提交 PDF,只在 README 给下载链接**(OSS / S3 / 网盘),clone 后跑脚本拉。

---

## 8. jsdelivr CDN 国内网速

**症状**:浏览器拉 `https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/...` 慢或失败,canvas 一直空白。

**解决**:本地 host PDF.js 库:
```bash
# 服务器
mkdir -p public/lib
curl -L -o public/lib/pdf.min.mjs \
  https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs
curl -L -o public/lib/pdf.worker.min.mjs \
  https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs
```

然后改 `viewer/pdf-renderer.js`:
```javascript
import * as pdfjs from '/lib/pdf.min.mjs';
pdfjs.GlobalWorkerOptions.workerSrc = '/lib/pdf.worker.min.mjs';
```

---

## 9. Docker 在 macOS 没起 — `Cannot connect to docker daemon`

**症状**:Mac 本地 `docker compose build` 报:
```
Cannot connect to the Docker daemon at unix:///Users/xxx/.docker/run/docker.sock
```

**解决**:启动 Docker Desktop,或 Colima。本地不一定要起 — 本 demo 直接在服务器
build,本地不动 docker。

---

## 总结清单(部署前 checklist)

部署同事项目前,逐条检查:

- [ ] PHP 项目用的是 nginx + php-fpm,不是 `php artisan serve`
- [ ] Range request 测试 206 而非 200(`curl -D - -H "Range: ..."`)
- [ ] Spring Boot 静态资源路径正确(无 `/static/` 前缀,或显式配置)
- [ ] nginx 反代加了 `proxy_buffering off`
- [ ] DPR 适配代码包含 `Math.max(DPR, 2)`
- [ ] PDF 走 LFS 或下载链接,不直接提交大文件
- [ ] PDF.js 库本地 host(国内环境)
