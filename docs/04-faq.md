# FAQ — 常见问题

## Q1: Windows 上看起来比 Mac 模糊?

**原因**:Mac retina 屏 `devicePixelRatio = 2`,Windows 普通屏 `= 1`。Mac 物理像素密度是 Windows 2 倍。

**修复**(本 demo 已实现):
```javascript
const dpr = Math.max(window.devicePixelRatio || 1, 2);  // 强制下限 2
const scale = (targetCssWidth / pdfPageWidth) * dpr * 2;  // × 2 oversample
```

`Math.max(dpr, 2)` 让 Windows 也按 retina 标准 oversample,canvas 物理像素增加 4 倍,弥补硬件密度差。

详见 [02-how-pdfjs-works.md](02-how-pdfjs-works.md) "DPR 跨平台适配"。

## Q2: 移动端会不会很慢?

PDF.js 在 iOS Safari / Android Chrome 性能可接受,但**首次拉 1.8 MB 的 pdf.min.mjs + worker.min.mjs** 会增加首屏延迟。

**优化**:
- 部署到本地 static 不走 CDN:`<script src="/static/pdfjs/pdf.min.mjs" type="module">`
- 移动端把 oversample 降到 1.5 倍(代码加 `if (window.innerWidth < 768) ...`)
- 用 thumbs/ 小图(独立 jpg)做导航条,主大图才用 PDF.js

## Q3: Range request 返回 200 不是 206 怎么办?

**最常见原因**:nginx 反代默认开 `proxy_buffering`,会把整个上游响应缓冲再吐给前端,Range 失效。

**修复** `nginx.conf`:
```nginx
proxy_buffering off;
proxy_request_buffering off;
```

**其他原因**:
- Laravel/Spring Boot 用了自定义 stream 响应而非默认 file response → 改回默认
- Apache 装了第三方模块改了 ETag → 看 `mod_headers` 配置
- CDN(Cloudflare 等)默认转发 Range,但有时缓存策略冲突 → 排查 CDN page rule

## Q4: 浏览器一次性下载整个 PDF 而不是 Range,什么原因?

```bash
curl -s -I -H "Range: bytes=0-100" "http://server/pdf/x.pdf" | head -3
```
看返回:
- `HTTP/1.1 206 Partial Content` ✅ 正常
- `HTTP/1.1 200 OK + Content-Length: 62914560` ❌ 后端没支持 Range

如果 curl 测试是 206 但浏览器还是拉全部:
- F12 Network 看 PDF.js 实际发的是 GET 还是 HEAD,Headers 有没有 `Range:`
- PDF.js 4.x 默认开启 streamRange,但有 fallback:如果服务器不支持就拉全部
- 老版本 PDF.js(< 3.x)需手动开 `disableStream: false`

## Q5: 文字能复制吗?

**目前**:本 demo 用纯 canvas 渲染,canvas 是位图,**文字不能选中复制**。

**解决方案**(进阶,本 demo 不做):用 PDF.js 官方推荐的 **canvas + textLayer 双层** 模式:
- canvas 负责视觉(图块、矢量线条)
- 透明 `<div class="textLayer">` 叠加在 canvas 上,内含 `<span>` 元素对应每个字符的精确位置
- 视觉:跟 canvas 一样
- 文字:用浏览器原生字体渲染,可选可复制

代价:实施复杂(字符定位、字体替换、滚动同步)。详见 PDF.js 官方 [examples/text-selection](https://github.com/mozilla/pdf.js/tree/master/examples)。

## Q6: 怎么"另存为图片"?为什么是 PNG 不是 JPG?

右键 canvas → "另存图像":浏览器默认调 `canvas.toBlob('image/png')`,**没用任何文件**,纯内存数据序列化。

PNG 是无损的,canvas 数据原汁原味保留。如果你想下载 JPG:
```javascript
canvas.toBlob(blob => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'page.jpg';
  a.click();
}, 'image/jpeg', 0.95);
```

## Q7: 不存 jpg,但是首页加载时就要拉 PDF metadata,是不是更慢?

**首次访问任意页**:
- PDF.js 拉 `Range: bytes=0-65535`(64 KB)→ 解析头 + xref 表
- 然后再拉具体页的字节范围
- 总下载量约 200-500 KB 就能渲首页

**对比传统 jpg**:
- 浏览器直接 `<img src="page_001.jpg">` → 1 个请求 ~400 KB

**结论**:**首页加载量基本一致**(~几百 KB)。但 PDF.js 后续切换页只需要几十 KB 增量,而 jpg 每页都得拉满。

## Q8: 现在做这套方案,未来想加文字搜索能"全文检索"吗?

**Yes**。PDF.js 还有 `page.getTextContent()` 返回页面所有文字 + 位置:

```javascript
const tc = await page.getTextContent();
tc.items.forEach(item => console.log(item.str, item.transform));  // 文字 + 位置矩阵
```

可以:
- 客户端 Ctrl+F 在已渲页面搜索 + 高亮(看 PDF.js 官方 viewer 的 `findController`)
- 服务器端预提取所有 PDF 文字到 ES / 数据库,做跨期搜索

但本 demo 不做。

## Q9: 同事的项目已经在用 jpg 方案,迁移成本大吗?

**前端改动**:把 `<img src="page_xxx.jpg">` 替换成 `<canvas data-page-num="N">` + 引入本 repo 的 `pdf-renderer.js`。~30 行 JS。

**后端改动**:
- 删除 PDF→JPG 的渲染步骤(可能是 ImageMagick / Ghostscript / PDFBox 那段代码)
- 加 1 个路由:`GET /pdf/{name}` 返回原 PDF 含 Range 支持(默认就有)
- 删除 jpg 静态资源服务

**回归测试**:1-2 期 PDF 端到端测,确认 viewer 正常 + Range 工作。

**可向后兼容**:模板里写 `{% if request.engine == 'jpg' %}<img>{% else %}<canvas>{% endif %}`,默认 canvas,出问题加 `?engine=jpg` 强制回退。本 demo 简化掉了 fallback,生产环境建议保留。
