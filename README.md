# 数字报纸 PDF.js 客户端渲染 demo

> **一句话**:浏览器直接渲染 PDF,服务器**不再生成/存储任何 jpg 页图**,省 50%+ 存储 + 矢量级清晰度。

PHP(Laravel)+ Java(Spring Boot)双语言 working demo,部署在 [159.203.0.28](http://159.203.0.28),为同事项目验证可行性。

---

## 这是什么

传统数字报站:`PDF → 服务器渲染所有页为 JPG → 存盘 → 浏览器 <img>`,每期 70 MB+,放大模糊。

本 demo 站:`PDF → 服务器只存原 PDF → 浏览器 PDF.js 用 <canvas> 矢量渲染`,每期省 50%+,放大无限清晰。

## 试一试

| 入口 | 说明 |
|---|---|
| [http://159.203.0.28:8091](http://159.203.0.28:8091) | Laravel 11 demo (nginx + php-fpm,海外节点)|
| [http://159.203.0.28:8092](http://159.203.0.28:8092) | Spring Boot 3.4 demo (海外节点)|
| 🪟 Windows 本地启动 | 见 [`deploy-windows-local/`](./deploy-windows-local/) — `mvn package` + `java -jar` 自己机器跑 |

两个 demo 显示同一份《中国传媒科技》2026 年第 2 期(60 MB,164 页)。

---

## Pipeline 全链路时序图

```
┌──── 用户浏览器 ────┐                ┌── 后端服务 (Java/PHP) ──┐
│                    │                │                          │
│ 1. 输入 URL        │── GET / ──────→│ 路由到 Controller         │
│                    │                │                          │
│                    │←── HTML ───────│ Thymeleaf/Blade 循环      │
│                    │   (含 164 个   │ 生成 164 个 <canvas>      │
│                    │    canvas 占位)│                          │
│                    │                │                          │
│ 2. 解析 HTML       │── GET .css ───→│ 静态文件 serve            │
│                    │── GET .js ────→│                          │
│                    │── GET pdf.min.mjs (gzip ~97KB)──────────→│ │
│                    │← 资源 ─────────│                          │
│                    │                │                          │
│ 3. JS 模块加载     │                │                          │
│  pdf-renderer.js   │                │                          │
│  ↓                 │                │                          │
│  pdfjs.getDocument │                │                          │
│  (url=/pdf/x.pdf)  │                │                          │
│                    │                │                          │
│ 4. PDF metadata    │── GET PDF ────→│ Spring/nginx 静态文件     │
│  Range: bytes=0-X  │  Range header  │ 自动响应 206              │
│                    │← 64 KB chunk ──│ (xref + 字体表)          │
│                    │  HTTP 206      │                          │
│                    │                │                          │
│ 5. PDF.js 解析:    │                │                          │
│  - numPages        │                │                          │
│  - 每页字节范围    │                │                          │
│                    │                │                          │
│ 6. IntersectionObs │                │                          │
│  监视所有 canvas   │                │                          │
│  视口前 500px 触发 │                │                          │
│                    │                │                          │
│ 7. 渲染该页:       │                │                          │
│  doc.getPage(N)    │── GET PDF ────→│                          │
│  → 拉 page N 字节  │ Range: bytes=..│                          │
│                    │← ~250 KB chunk │                          │
│                    │  HTTP 206      │                          │
│                    │                │                          │
│ 8. PDF.js 栅格化:  │                │                          │
│  - worker 解析操作 │                │                          │
│  - 矢量 → 像素     │                │                          │
│  - drawImage 到    │                │                          │
│    <canvas>        │                │                          │
│                    │                │                          │
│ 9. 用户看到该页    │                │                          │
│                    │                │                          │
│ 滚动 → 重复 6-9    │                │                          │
└────────────────────┘                └──────────────────────────┘
```

**关键观察**:服务端始终只是"傻瓜文件服务器",从不渲染 PDF。所有渲染都发生在用户浏览器里,服务器不会因被访问而产生任何新文件。

---

## 数据流字节量(测算)

164 页杂志,假设用户翻完全本:

| 阶段 | 字节量 |
|---|---|
| HTML 主页 | ~5 KB |
| pdf-renderer.js(自家代码)| ~3 KB |
| styles.css | ~2 KB |
| pdf.min.mjs(gzip)| ~97 KB(7 天缓存,只第一次)|
| pdf.worker.min.mjs(gzip)| ~400 KB(同上)|
| PDF metadata 初始 Range | ~50–200 KB |
| 每页字节(平均) | ~250 KB(矢量原语 + 嵌入字体子集)|
| 翻完 164 页 PDF 字节 | ~40 MB |
| **首次访问总流量** | **~40.5 MB** |
| **缓存后回访** | **~40 MB**(库已缓存)|

---

## 与传统 jpg 方案对比

| | 传统 jpg | PDF.js (本 demo) |
|---|---|---|
| 服务器存什么 | 60 MB PDF + 70 MB jpg(154 页 × 400KB)| **60 MB PDF only** |
| 服务器 CPU | 录入时一次性渲染 30s+ | **0**(永不渲染)|
| 客户端要的库 | 无 | pdf.min.mjs ~97 KB(gzip)|
| 第一页加载量 | 1 张 jpg ~400 KB | 库 + metadata ~650 KB |
| 翻一页加载量 | 新 jpg ~400 KB | 新页字节 ~250 KB |
| 全本流量 | ~65 MB | ~40 MB |
| 放大到 200%+ | 模糊(1800px 上限)| **矢量级清晰** |
| 跨平台清晰度 | 一致 | Mac retina 完美;Windows 需 DPR oversample(已做)|
| **每天的存储增长** | 每入库 1 期 +70 MB jpg | **0**(只新增 60 MB PDF)|

---

## 如何证明没有额外的存储占用

担心 demo 跑久了"偷偷"在某处缓存渲染产物?提供两层证明:

### 证明 1:静态时刻 — 服务器上根本没有 jpg

```bash
bash tools/verify-no-jpg.sh   # 一键 6 角度核查
```

包含:
1. **容器内全盘搜图**:`find / -name '*.jpg' -o -name '*.png' -o -name '*.webp'` 仅 favicon 等静态资源,无任何"页图"
2. **入像目录扫描**:`du -h /app/storage/` 不存在 page-renderer 目录
3. **代码静态分析**:Controller 中无任何 ImageWriter / GD / Imagick / pdf2image 调用
4. **Docker image layer**:`docker history` 没有渲染步骤
5. **网络抓包**:浏览器 Network 面板看到的全是 `application/pdf` 206 响应,没有 `image/jpeg`
6. **依赖清单审计**:composer.json / pom.xml 无 imagick / pdfbox-rendering / pdf2image

详见 [docs/06-storage-proof.md](docs/06-storage-proof.md)。

### 证明 2:持续运行不增长 — 跑 100 次后字节级一致

```bash
bash tools/verify-no-growth.sh   # 前后快照对比
```

执行流程:
1. 抓取访问前**全文件清单**(每个文件的字节大小、修改时间、inode)
2. 模拟 **100 次浏览器访问**(主页 + Range PDF + 静态资源 + 翻页)
3. 抓取访问后清单
4. `diff` 应为空 → **0 个文件新增 / 修改 / 删除**
5. 字节级 `du -sb` 增长 < 200 KB(那是 nginx access log,无任何图片产物)

**关键检查**:diff 输出**不能含 `.jpg`/`.png`/`.webp`/`.gif`** — 出现即视为破防。

### 为什么这是充分证明

- ✅ **静态层面**没有任何渲染代码路径,后端连"会画图"的库都没装
- ✅ **运行时层面**100 次访问后磁盘不变,说明请求处理只读不写
- ✅ **架构层面**:渲染发生在浏览器 JS 引擎里,**完全无法**触达服务器磁盘

服务器与"jpg/png 页图"在每个层面都是物理隔离的。

---

## 文档导航

| 看哪 | 看什么 |
|---|---|
| [docs/01-why-no-jpg.md](docs/01-why-no-jpg.md) | 为什么这样省存储 + 矢量精度优势(数据对比)|
| [docs/02-how-pdfjs-works.md](docs/02-how-pdfjs-works.md) | PDF.js + canvas + Range request 三件套原理 |
| [docs/03-deployment.md](docs/03-deployment.md) | nginx 配置 + 后端必须的 routes(PHP/Java 两边都讲)|
| [docs/04-faq.md](docs/04-faq.md) | 常见问题(Windows DPR 模糊、移动端、CORS 等)|
| [docs/05-pitfalls.md](docs/05-pitfalls.md) | ⭐ **9 个工程坑实录**(部署本 demo 时实际撞过的)|
| [docs/06-storage-proof.md](docs/06-storage-proof.md) | ⭐ **存储证明**:6 个角度证明真没存 jpg |
| [tools/verify-no-jpg.sh](tools/verify-no-jpg.sh) | 静态时刻:一键运行所有证明,产出报告 |
| [tools/verify-no-growth.sh](tools/verify-no-growth.sh) | 持续运行:模拟 100 次访问前后字节对比 |

---

## 仓库结构

```
.
├── docs/         全语言无关教学文档(必读)
├── viewer/       通用前端(任何后端可对接)
│   ├── pdf-renderer.js   核心 80 行 JS
│   ├── index.html        demo 页
│   └── styles.css
├── php/          Laravel 11 最小 demo
├── java/         Spring Boot 3.4 最小 demo
├── deploy/       docker-compose + nginx 配置(海外服务器)
├── deploy-windows-local/  Windows 本地启动指南(mvn build + java -jar)
└── tools/        证明脚本(verify-no-jpg / verify-no-growth)
```

---

## 不解决什么

本 repo 只演示**前端 PDF 渲染技术**,不涉及:

- ❌ PDF 内容解析(OCR、文字提取、文章结构化)
- ❌ AI / LLM / Anthropic API
- ❌ 用户登录、权限、数据库
- ❌ 内容编辑器

如果你的项目需要完整的 PDF→结构化数据 pipeline,看姊妹仓库 `digital-magazine-platform`(私有)。本 demo 只是"展示出来"那一段。

## 快速本地起跑

```bash
git clone https://github.com/xiaotianlou/digital-magazine-platform-blueprint
cd digital-magazine-platform-blueprint
docker compose -f deploy/docker-compose.yml up
# 浏览器开 http://localhost:8091 (PHP) 或 http://localhost:8092 (Java)
```
