# PDF.js + canvas + Range request 三件套原理

> 看完这页,你就知道为什么"浏览器直接渲染 PDF + 服务器只存原 PDF"是可行的。

## 整体数据流

```
                ┌─────────────────────┐
                │ 服务器(只存 PDF)│
                │  source.pdf 60 MB   │
                └──────────┬──────────┘
                           │
        HTTP GET + Range:  │
        bytes=0-65535      │  (只取 64 KB!)
                           │
                           ▼
            ┌──────────────────────────┐
            │     浏览器(主 thread)│
            │                          │
            │  PDF.js 解析 PDF 元数据  │
            │  ↓                       │
            │  按需 Range request 取页 │
            │  ↓                       │
            │  解析当前页矢量原语      │
            │  (字形 path、线、图像)│
            └──────────┬───────────────┘
                       │ postMessage
                       ▼
            ┌──────────────────────────┐
            │ pdf.worker(背景 thread) │
            │  栅格化矢量到像素        │
            │  → 输出 ImageData        │
            └──────────┬───────────────┘
                       │
                       ▼
            ┌──────────────────────────┐
            │  <canvas> 元素           │
            │  ctx.drawImage()         │
            └──────────────────────────┘
```

## 第 1 件事:PDF.js(纯 JS 库)

[PDF.js](https://mozilla.github.io/pdf.js/) 是 Mozilla 维护的纯 JavaScript 库,Firefox 浏览器内置 PDF 阅读器就是它。

**它做的事**:
1. 用 JavaScript 解析 PDF 二进制格式(就是 Adobe 那个 PDF)
2. 把页面里的"绘图指令"(画线、画字形、贴图像)依次执行,栅格化到 `<canvas>`

**关键点**:
- **不需要服务器渲染** — 浏览器自己解析 PDF
- **矢量级精度** — 文字/线条直接画 path,不是 jpg 像素
- **支持页面对象延迟加载** — 不用一次拉整本 PDF

加载方式:
```html
<script type="module">
  import * as pdfjs from 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs';
  pdfjs.GlobalWorkerOptions.workerSrc =
    'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs';

  const doc = await pdfjs.getDocument('/path/to/source.pdf').promise;
  const page = await doc.getPage(1);
  // ... 渲染
</script>
```

或者本地 host(不依赖 CDN):把 `pdf.min.mjs` + `pdf.worker.min.mjs` 放服务器 `static/`。

## 第 2 件事:HTTP Range Request

PDF.js 默认开启**字节范围请求**,只下载视口需要的部分。

普通 HTTP 请求:
```http
GET /pdf/source.pdf HTTP/1.1
Host: example.com

→ HTTP/1.1 200 OK
→ Content-Length: 62914560  (60 MB,全部内容)
```

带 Range:
```http
GET /pdf/source.pdf HTTP/1.1
Host: example.com
Range: bytes=0-65535        (只要前 64 KB)

→ HTTP/1.1 206 Partial Content    (注意是 206 不是 200!)
→ Accept-Ranges: bytes
→ Content-Range: bytes 0-65535/62914560
→ Content-Length: 65536
→ (only 64 KB 数据)
```

**后端必须支持这个**。否则 PDF.js 退回拉整个 60 MB,延迟差几十倍。

### 各框架默认支持情况

| 后端 | Range 默认支持 | 备注 |
|---|---|---|
| Laravel `response()->file()` | ✅ | BinaryFileResponse 自带 |
| Spring Boot `Resource` | ✅ | ResourceHttpRequestHandler 自带 |
| nginx static file | ✅ | 默认 |
| Apache static file | ✅ | 默认 |
| FastAPI `FileResponse` | ✅ | Starlette 自带 |
| Express.js `sendFile` | ✅ | 默认 |
| Flask `send_file` | ❌ | 需手工加 conditional=True |
| nginx `proxy_pass` 透传 | ⚠️ | **必须 `proxy_buffering off`** |

### 验证 Range 是否工作

```bash
curl -s -D - -o /dev/null -H "Range: bytes=0-100" \
  "http://your-server/pdf/source.pdf" | head -8
```

应该看到:
```
HTTP/1.1 206 Partial Content       ← 关键!不是 200
Accept-Ranges: bytes
Content-Range: bytes 0-100/62914560
Content-Length: 101
```

如果是 `200 OK + Content-Length: 62914560`,说明 Range 没工作,要排查后端配置。

## 第 3 件事:IntersectionObserver(懒加载)

整本杂志 164 页,如果一次性渲染所有 canvas,浏览器内存会爆 + 首屏卡顿。

用 [IntersectionObserver](https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API) 让 PDF.js 只渲"视口附近"的页:

```javascript
const io = new IntersectionObserver(entries => {
  for (const e of entries) {
    if (e.isIntersecting) renderCanvas(e.target);  // 滚到附近才渲染
  }
}, { rootMargin: '500px' });  // 进入视口前 500px 就开始渲染

document.querySelectorAll('canvas.pdf-page').forEach(c => io.observe(c));
```

效果:
- 首屏:只渲首页
- 用户滚动:相邻 1-2 页提前渲染
- 浏览器内存控制在 ~50 MB(每个 canvas ~10 MB)

## 第 4 件事(易踩坑):DPR 跨平台适配

Mac retina 屏 `devicePixelRatio = 2`,Windows 普通屏 `= 1`。

如果你简单写:
```javascript
const scale = targetCssWidth / pdfPageWidth;
const vp = page.getViewport({scale});
```

**Mac 看清楚,Windows 模糊**,因为 canvas 物理像素只有屏幕物理像素的一半。

正确做法:
```javascript
const dpr = Math.max(window.devicePixelRatio || 1, 2);  // 强制下限 2
const scale = (targetCssWidth / pdfPageWidth) * dpr * 2;  // × 2 oversample
const vp = page.getViewport({scale});
canvas.width = vp.width;     // 物理像素(高分辨率)
canvas.height = vp.height;
canvas.style.width = targetCssWidth + 'px';   // CSS 像素(显示尺寸)
```

**为什么 × dpr × 2**:
- × dpr:让 canvas 物理像素匹配屏幕物理像素
- × 2 (oversample):画质再上一档,浏览器下采样使文字更锐
- `Math.max(dpr, 2)`:Windows DPR=1 也按 retina 标准渲染

## 第 5 件事(精度提升):intent='print' + 高质量

```javascript
const ctx = canvas.getContext('2d', { alpha: false });
ctx.imageSmoothingEnabled = true;
ctx.imageSmoothingQuality = 'high';

await page.render({
  canvasContext: ctx,
  viewport: vp,
  intent: 'print',   // ← 让 PDF.js 走最高质量路径(更精的字形 hinting)
}).promise;
```

`intent: 'print'` 是 PDF.js 内部参数,不是字面打印。它告诉 PDF.js"这是高精度场景,字形/线宽用 print-quality 路径"。

## 总结:三件事 + 两个调教

| | |
|---|---|
| **三件事(必须)** | PDF.js + Range request + IntersectionObserver |
| **两个调教(强烈推荐)** | DPR oversample + intent='print' |

加起来 ~80 行 JS。看 [`viewer/pdf-renderer.js`](../viewer/pdf-renderer.js) 完整代码。
