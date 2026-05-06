# viewer/ — 通用前端

任何后端框架(PHP/Java/Python/Node/Go)都能直接用这套前端。

## 文件清单

| 文件 | 用途 |
|---|---|
| `pdf-renderer.js` | 核心 ~80 行,PDF.js 渲染逻辑(lazy + DPR 适配)|
| `index.html` | demo 页(前 8 页 canvas 占位)|
| `styles.css` | 简洁通用样式 |

## 后端要做的(就 2 件事)

### 1. 提供 HTML(任意路由)

```html
<body data-pdf-url="/pdf/source.pdf">
  ...
  <canvas class="pdf-page" data-page-num="1"></canvas>
  <canvas class="pdf-page" data-page-num="2"></canvas>
  ...
  <script type="module" src="/static/pdf-renderer.js"></script>
</body>
```

`data-pdf-url` 的值是后端能访问的 PDF 路径。`data-page-num` 从 1 开始。

### 2. 提供 PDF 文件 + Range 支持

```
GET /pdf/source.pdf
Range: bytes=0-65535
→ HTTP/1.1 206 Partial Content        ← 必须 206
→ Content-Type: application/pdf
→ Accept-Ranges: bytes
→ Content-Range: bytes 0-65535/62914560
```

**主流框架默认就支持**:
- Laravel `response()->file()` ✅
- Spring Boot `Resource` ✅
- nginx static file ✅
- FastAPI `FileResponse` ✅
- Express `sendFile` ✅

**坑**:nginx 反代时务必加 `proxy_buffering off`,否则 Range 被吞。

## 用法 1:auto-init from `data-pdf-url`

最简洁,在 `<body>` 加 `data-pdf-url` 属性即可:

```html
<body data-pdf-url="/pdf/source.pdf">
```

JS 末尾自动检测并启动渲染。

## 用法 2:手动 init

```html
<script type="module">
  import { initPdfRenderer } from '/viewer/pdf-renderer.js';
  initPdfRenderer({
    pdfUrl: '/pdf/source.pdf',
    lazy: true,           // 默认 true,IntersectionObserver 懒加载
    oversample: 2,        // 默认 2,降到 1 可省内存(代价是清晰度)
  });
</script>
```

## 性能调优

| 场景 | 调整 |
|---|---|
| 移动端 / 低端设备 | `oversample: 1.5` |
| 文档极短(< 5 页) | `lazy: false` 一次渲完 |
| PDF 极大(> 200 MB) | 加 `rangeChunkSize: 32768` 减小每次拉的字节 |
| 网络很慢 | 把 PDF.js 库本地 host(去掉 jsdelivr CDN 依赖) |
| 想要文字可选 | 看 docs/04-faq.md Q5,需 textLayer 双层 |

## 点击放大 modal

`<div id="imgModal">` 已包含在 index.html。点 canvas 自动弹大图(canvas → PNG 序列化)。

如果不想要,删掉 modal HTML 即可,JS 会自动跳过(if modal not found, skip)。

## 完整示例

打开 `index.html` 直接看渲染效果(只要服务器同目录有 `pdf/source.pdf` 即可)。

参考 `php/` 和 `java/` 目录下的具体框架实现。
