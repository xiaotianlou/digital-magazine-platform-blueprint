# 为什么不存 jpg —— 存储 + 精度双赢

## 传统做法的代价

数字报站常见架构:

```
PDF 上传
   ↓
服务器渲染所有页(用 ImageMagick / Ghostscript / Apache PDFBox)
   ↓
保存 page_001.jpg, page_002.jpg, ... 到磁盘
   ↓
浏览器 <img src="/static/pages/xxx/page_001.jpg">
```

**问题**:

| 项 | 数字 |
|---|---|
| 1 期杂志(164 页 @ 1800px JPG q=88) | ~70 MB |
| 100 期 | ~7 GB |
| 1000 期(5 年存档) | ~70 GB |
| 服务器渲染时间(单期) | +30~60 秒(I/O + Ghostscript) |
| 上传带宽 | 70 MB / 期 |
| **致命伤**:用户放大查看 | **栅格化**,1800px 上限 → 放大 200% 就糊 |

## 本 demo 做法

```
PDF 上传
   ↓
服务器**只**存 source.pdf
   ↓
(无渲染步骤)
   ↓
浏览器 <canvas> + PDF.js 拉 source.pdf(HTTP Range request)
   ↓
客户端**矢量**渲染到 canvas(每页约 100-300ms)
   ↓
IntersectionObserver lazy 加载(滚到附近才渲染)
```

## 数字对比

| 项 | 传统 jpg | 本 demo |
|---|---|---|
| 1 期占用 | 70 MB jpg + 60 MB pdf = **130 MB** | 60 MB pdf only |
| 100 期 | 13 GB | 6 GB |
| 1000 期 | 130 GB | 60 GB |
| **节省比例** | — | **~54%** |
| 录入处理时间 | +30~60s 渲染 | **0**(无渲染) |
| 视觉精度 | 1800px 栅格(放大 200% 模糊) | **矢量**(放大无限清晰) |
| 跨设备清晰度 | Mac retina + 普通 Windows 均 OK | 需 DPR 适配(本 demo 已处理)|
| 浏览器加载量 | 全本一次性 ~70 MB | 视口 lazy,~几 KB-几 MB / 页 |

## 关键技术原理

实现这个方案需要 **3 件事同时成立**:

1. **PDF.js**(Mozilla 出品的纯 JS 库) — 浏览器解析 PDF + 渲染到 `<canvas>`
2. **HTTP Range request** — 后端必须支持,PDF.js 才能"只下载视口需要的字节"
3. **IntersectionObserver** — JS 浏览器 API,滚动到接近时才触发渲染,避免一次性渲所有页

详见 [02-how-pdfjs-works.md](02-how-pdfjs-works.md)。

## 什么时候**不**适合用这个方案

- ⚠️ 必须支持 IE / 古老 Android(< 2018):PDF.js 兼容性可能不够 → 仍要 jpg fallback
- ⚠️ 移动端要做"先看总览再决定打开":需要薄缩略图(thumbs/),thumbs 不能彻底省
- ⚠️ PDF 内容是手稿扫描件(整页就是大栅格图):矢量精度无意义,jpg 反而压缩更狠
- ⚠️ 需要 SEO 索引页内容:浏览器 canvas 渲染对爬虫不友好,需要 textLayer 透明叠加(本 demo 不做)

否则,**本方案对学术期刊、报纸、设计杂志、产品手册等任何"原 PDF 文字+图混排"内容,都是显著优于 jpg 的方案**。
