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
| [http://159.203.0.28/demo-php](http://159.203.0.28/demo-php) | Laravel 11 demo |
| [http://159.203.0.28/demo-java](http://159.203.0.28/demo-java) | Spring Boot 3.4 demo |

两个 demo 显示同一份《中国传媒科技》2026 年第 2 期(60 MB,164 页)。

## 文档导航

| 看哪 | 看什么 |
|---|---|
| [docs/01-why-no-jpg.md](docs/01-why-no-jpg.md) | 为什么这样省存储 + 矢量精度优势(数据对比)|
| [docs/02-how-pdfjs-works.md](docs/02-how-pdfjs-works.md) | PDF.js + canvas + Range request 三件套原理 |
| [docs/03-deployment.md](docs/03-deployment.md) | nginx 配置 + 后端必须的 routes(PHP/Java 两边都讲)|
| [docs/04-faq.md](docs/04-faq.md) | 常见问题(Windows DPR 模糊、移动端、CORS 等)|

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
└── deploy/       docker-compose + nginx 配置
```

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
