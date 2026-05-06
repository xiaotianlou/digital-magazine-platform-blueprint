# Laravel 11 + PHP 8.3-fpm + nginx minimal demo
# 用 nginx + php-fpm 因为 `php artisan serve` 内置 server 不支持 HTTP Range header
# build: docker build -t magazine-php-demo .
# run:   docker run -p 8091:80 magazine-php-demo
FROM php:8.3-fpm-alpine

WORKDIR /app

# 系统依赖 + nginx + supervisord(同时跑 nginx 和 php-fpm)
RUN apk add --no-cache \
    libzip-dev git curl bash unzip nginx supervisor \
    && docker-php-ext-install zip

# composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Laravel 框架(create-project)
RUN composer create-project laravel/laravel . "11.*" --prefer-dist --no-interaction \
    && rm -rf .git tests/

# 我们的自定义文件
COPY routes/web.php routes/web.php
COPY app/Http/Controllers/PdfController.php app/Http/Controllers/PdfController.php
COPY resources/views/viewer.blade.php resources/views/viewer.blade.php
COPY public/ public/

# Laravel 配置 + 权限
RUN cp .env.example .env \
    && php artisan key:generate --force \
    && mkdir -p storage/framework/{cache,sessions,views} bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache \
    && sed -i 's|^SESSION_DRIVER=.*|SESSION_DRIVER=file|' .env \
    && sed -i 's|^CACHE_STORE=.*|CACHE_STORE=file|' .env \
    && sed -i 's|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=sync|' .env \
    && php artisan config:clear

# nginx 配置(serve Laravel public/ + 反代 PHP-FPM + gzip 优化)
COPY <<'NGINX_CONF' /etc/nginx/http.d/default.conf
# gzip 压缩 — JS/CSS 减 60%,国内网速关键
gzip on;
gzip_vary on;
gzip_min_length 1024;
gzip_comp_level 6;
gzip_types text/plain text/css text/javascript application/javascript application/json application/x-javascript application/xml application/wasm;
# ⚠️ PDF 不在 gzip_types 里 — 已经压缩过的不要再 gzip(浪费 CPU 还可能搞坏 Range)

server {
    listen 80 default_server;
    server_name _;
    root /app/public;
    index index.php index.html;

    # 静态文件直接 serve(包括 PDF — nginx 自带 Range 支持!)
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # 静态资源加缓存头(JS/CSS/lib/)
    location ~* \.(js|mjs|css|ico)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    # PHP 走 php-fpm
    location ~ \.php$ {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # 大 PDF 文件:nginx 静态 serve(自动支持 Range)
    client_max_body_size 100M;
    sendfile on;
    keepalive_timeout 65;
}
NGINX_CONF

# supervisord 同时跑 nginx + php-fpm
COPY <<'SUPERVISOR_CONF' /etc/supervisord.conf
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0

[program:php-fpm]
command=php-fpm -F
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
autorestart=true

[program:nginx]
command=nginx -g 'daemon off;'
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
autorestart=true
SUPERVISOR_CONF

EXPOSE 80

CMD ["supervisord", "-c", "/etc/supervisord.conf"]
