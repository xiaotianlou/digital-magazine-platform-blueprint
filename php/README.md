# PHP Laravel 11 demo

最小 Laravel 11 项目,演示 PDF.js 客户端矢量渲染。**仅 2 个自定义路由** + 复用 viewer/ 静态资源。

## 文件清单

```
php/
├── composer.json                          # 仅 laravel/framework 依赖
├── routes/web.php                         # 2 个路由
├── app/Http/Controllers/PdfController.php # PDF 文件 serve(BinaryFileResponse 自带 Range)
├── resources/views/viewer.blade.php       # HTML 模板(套 viewer/index.html)
├── public/
│   ├── pdf/chuanmei_2026_02.pdf           # demo PDF(60 MB,164 页)
│   └── static/                            # pdf-renderer.js + styles.css
└── Dockerfile                             # composer create-project 装 Laravel + 覆盖自定义文件
```

## 本地跑(无 docker)

需要本机有 PHP 8.2+ 和 composer。

```bash
cd php/
composer create-project laravel/laravel laravel-base "11.*"  # 拉 Laravel 框架
cp routes/web.php laravel-base/routes/web.php
cp app/Http/Controllers/PdfController.php laravel-base/app/Http/Controllers/
cp resources/views/viewer.blade.php laravel-base/resources/views/
cp -r public/static public/pdf laravel-base/public/
cd laravel-base
cp .env.example .env
php artisan key:generate
php artisan serve --port=8091
# 浏览器开 http://localhost:8091
```

## Docker 跑(推荐,无 PHP 环境也能起)

```bash
cd php/
docker build -t magazine-php-demo .
docker run -p 8091:8091 magazine-php-demo
# 浏览器开 http://localhost:8091
```

## 验证

1. 浏览器看到 Laravel 默认页样式 + 164 个 canvas 页占位
2. F12 → Network → 看 `chuanmei_2026_02.pdf` 是 `206 Partial Content`
3. 滚动:新页 lazy 渲染,旧页保留
4. 点击任何 canvas:弹放大 modal

## 关键代码 vs Java 版对比

| | PHP (Laravel) | Java (Spring Boot) |
|---|---|---|
| **PDF serve 路由** | `response()->file($path, [headers])` | `ResponseEntity.ok().headers().body(Resource)` |
| **Range 支持** | BinaryFileResponse 自带 | ResourceHttpRequestHandler 自带 |
| **模板引擎** | Blade(`@for`、`{{ }}`) | Thymeleaf(`th:each`、`th:text`) |
| **静态资源** | `asset()` helper → `public/` | `/static/` 自动映射 `resources/static/` |

两边复杂度几乎相同 — 因为 demo 本身只是"serve PDF + 套 HTML"。
