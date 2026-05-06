# 存储证明 — 怎么证明真的没用 jpg

> 仅说"看,目录下没 page_*.jpg" 说服力不够 — 可能 jpg 藏在别处、镜像层里、缓存里。本页给**严格的多角度证明方法**。

## 证明 1:容器内文件系统全盘扫描 jpg

```bash
# PHP 容器
docker exec magazine-php-demo find / \
  -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) \
  -size +50k 2>/dev/null

# Java 容器
docker exec magazine-java-demo find / \
  -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) \
  -size +50k 2>/dev/null
```

**期望**:**完全空输出**(没找到任何 50 KB+ 的图)。

如果有输出,可能是:
- Laravel/Spring 框架自带的 favicon / logo(< 50 KB,所以加了 size 过滤)
- PDF 内嵌的图(那是 PDF 的一部分,不是单独的 jpg 文件)

## 证明 2:Docker image 总大小

```bash
docker images magazine-php-demo magazine-java-demo --format \
  "table {{.Repository}}\t{{.Size}}"
```

**期望**:每个 image ~200-400 MB(框架 + JRE/PHP-FPM + 60 MB PDF + 必要库)。
这就是真实的"占用"。

## 证明 3:网络流量证据(浏览器侧)

打开 Chrome F12 → Network → 刷新页面 → 看请求:

```
请求清单:
✅ GET /                      文档 HTML, ~1 KB
✅ GET /pdf-renderer.js       JS 库, ~3 KB
✅ GET /styles.css            ~2 KB
✅ GET .../pdf.min.mjs        PDF.js (CDN 或本地), 1.8 MB
✅ GET /pdf/xxx.pdf           Range bytes=0-65535, 64 KB     ← 206 不是 200
✅ GET /pdf/xxx.pdf           Range bytes=65536-..., 64 KB
   ...更多 Range 请求
❌ GET /pages/page_001.jpg    应该 0 个       ← 关键!
❌ GET /thumbs/...            应该 0 个
❌ GET /static/pages/...      应该 0 个
```

只要 Network 面板里**没有任何 .jpg 请求**,就证明前端从来没拿过 jpg。
配合证明 1(后端没存 jpg),前后端闭环。

## 证明 4:Image 层级分析

```bash
docker history magazine-php-demo --no-trunc --format \
  "table {{.Size}}\t{{.CreatedBy}}"
```

可以看到**哪一步增加了多少 MB**。如果某层有 `RUN convert pdf png ...`,说明镜像内有 jpg。本 demo 镜像层只有:
```
~ 50 MB  apk add nginx php-fpm
~ 100 MB composer create-project laravel
~ 60 MB  COPY public/pdf/chuanmei_2026_02.pdf  ← 唯一大文件,是 PDF 不是 jpg
~ 5 MB   COPY public/static/  (pdf-renderer.js + styles.css)
```

## 证明 5:对比版本(可选,最有说服力)

跑一个"传统 jpg" 版本镜像,对比磁盘占用:

```bash
# 假设有个传统版 image: magazine-php-traditional(用 ImageMagick 渲染所有页)
docker images magazine-php-traditional   # ~ 350 MB(PHP + 60 MB PDF + 70 MB jpg pages/)
docker images magazine-php-demo          # ~ 280 MB(PHP + 60 MB PDF,无 jpg)

# 容器内 du
docker exec magazine-php-traditional du -sh /app/public/    # 130+ MB
docker exec magazine-php-demo        du -sh /app/public/    # 60 MB
```

差 70 MB / 期 = **方案的实际节省**。

(本 repo 没建传统版镜像,因为要这么大对比工程量太大;但同事项目要立这个 KPI 数据的话可以加)

## 证明 6:CI 检查(保证未来不退化)

写个 GitHub Action 防止有人不小心提交 jpg:

```yaml
# .github/workflows/no-jpg-check.yml
name: No JPG check
on: [push, pull_request]

jobs:
  check-no-jpg:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: |
          # 项目里不应有任何 jpg/png(除了非常少的 < 50KB 的 logo/icon)
          BIG_IMGS=$(find . -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) \
            -not -path "./.git/*" -size +50k)
          if [ -n "$BIG_IMGS" ]; then
            echo "❌ Found large images:"
            echo "$BIG_IMGS"
            exit 1
          fi
          echo "✅ No big jpg/png in repo"
```

任何人提交 50 KB+ 的 jpg/png,CI 就 fail,立刻发现。

## 一键证明脚本

本仓库提供 `tools/verify-no-jpg.sh`,跑一次得到完整的多角度报告:

```bash
bash tools/verify-no-jpg.sh
```

---

## 综合性陈述(给领导/同事看的话)

> "本方案不存任何 page jpg。证明:
> (1) 容器内 `find / -name '*.jpg' -size +50k` 输出为空;
> (2) 浏览器 Network 面板**零** jpg 请求,只有 PDF Range request 返回 206;
> (3) Docker image 层级分析,唯一 60 MB+ 的 layer 是 PDF 本身,不是渲染产物;
> (4) CI 卡点防退化。
> 任何一项失败都说明 jpg 偷偷藏在某处了。"
