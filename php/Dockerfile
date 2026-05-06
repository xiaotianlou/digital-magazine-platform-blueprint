# Laravel 11 + PHP 8.3 minimal PDF.js demo
# build: docker build -t magazine-php-demo .
# run:   docker run -p 8091:8091 -v $(pwd)/public/pdf:/app/public/pdf magazine-php-demo
FROM php:8.3-cli-alpine

WORKDIR /app

# 系统依赖
RUN apk add --no-cache libzip-dev git curl bash unzip \
    && docker-php-ext-install zip pdo_sqlite

# composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# 1. 装一份 Laravel 11 骨架(framework + 默认 boilerplate)
RUN composer create-project laravel/laravel . "11.*" --prefer-dist --no-interaction \
    && rm -rf .git .editorconfig phpunit.xml tests/

# 2. 覆盖 — 我们的自定义文件
COPY routes/web.php routes/web.php
COPY app/Http/Controllers/PdfController.php app/Http/Controllers/PdfController.php
COPY resources/views/viewer.blade.php resources/views/viewer.blade.php

# 3. public/ 资源(PDF + 复制 viewer/ 的静态文件)
COPY public/ public/

# 4. 准备 storage 权限 + .env
RUN cp .env.example .env \
    && php artisan key:generate --force \
    && mkdir -p storage/framework/{cache,sessions,views} bootstrap/cache \
    && chmod -R 777 storage bootstrap/cache \
    && php artisan config:clear

EXPOSE 8091

# 用 Laravel 内置 server(demo 简洁,生产环境换 nginx+php-fpm)
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8091"]
