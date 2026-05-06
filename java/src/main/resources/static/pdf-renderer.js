/**
 * PDF.js 客户端矢量渲染 — 通用版,任何后端可用
 *
 * 用法:
 *   <canvas class="pdf-page" data-page-num="1"></canvas>
 *   <canvas class="pdf-page" data-page-num="2"></canvas>
 *   ...
 *   <script type="module">
 *     import { initPdfRenderer } from '/viewer/pdf-renderer.js';
 *     initPdfRenderer({ pdfUrl: '/pdf/source.pdf' });
 *   </script>
 *
 * 后端要求:
 *   1. /pdf/source.pdf 必须支持 HTTP Range (响应 206 Partial Content)
 *   2. 返回 Content-Type: application/pdf
 *
 * 失败兜底:
 *   - PDF.js 库加载失败(CDN 不通)→ 显示错误条 + 提供 PDF 下载链接
 *   - getDocument 超时 30s → 同上
 *   - 单页渲染失败 → 该 canvas 显示提示,其他页继续
 */

import * as pdfjs from 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs';
pdfjs.GlobalWorkerOptions.workerSrc =
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs';

// 全局错误展示
function showGlobalError(msg, pdfUrl) {
  const banner = document.createElement('div');
  banner.style.cssText = 'position:fixed;top:0;left:0;right:0;background:#c0392b;color:#fff;padding:14px 22px;z-index:9999;font:14px sans-serif;text-align:center;box-shadow:0 2px 8px rgba(0,0,0,.2)';
  banner.innerHTML = `⚠️ ${msg} <a href="${pdfUrl}" target="_blank" style="color:#fff;margin-left:10px;text-decoration:underline">下载原 PDF</a> · <a href="javascript:location.reload()" style="color:#fff;text-decoration:underline">刷新</a>`;
  document.body.prepend(banner);
}

function showPageError(canvas, msg) {
  const wrap = canvas.parentElement;
  const note = document.createElement('div');
  note.style.cssText = 'background:#fdf3e8;border:1px solid #e8a87c;color:#8b4d1c;padding:10px;border-radius:4px;font-size:.85em;text-align:center';
  note.textContent = `第 ${canvas.dataset.pageNum} 页加载失败:${msg}`;
  wrap.replaceChild(note, canvas);
}

// 给 promise 加超时
function withTimeout(promise, ms, label) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() =>
      reject(new Error(`${label} 超时 (${ms}ms)`)), ms))
  ]);
}

export async function initPdfRenderer({ pdfUrl, lazy = true, oversample = 2, docTimeout = 30000 } = {}) {
  if (!pdfUrl) throw new Error('pdfUrl required');

  // 拉 PDF 元数据 + 准备 doc 对象(Range request 自动开启)
  // 套 30 秒超时:网络不通时不会一直转
  const docPromise = withTimeout(
    pdfjs.getDocument({
      url: pdfUrl,
      rangeChunkSize: 65536,    // 每次 Range 拉 64 KB
      disableStream: false,     // 启用 streaming
    }).promise,
    docTimeout,
    'PDF 加载'
  );

  // 整体失败兜底:doc 拉不到就 banner 提示
  docPromise.catch(err => {
    console.error('[pdf-renderer] doc fail:', err);
    showGlobalError(`PDF 加载失败:${err.message}`, pdfUrl);
  });

  // 单页渲染
  async function renderCanvas(canvas) {
    if (canvas.dataset.rendered) return;
    canvas.dataset.rendered = 'pending';
    try {
      // 该页渲染单独 30s 超时(防 PDF.js 内部死循环或 worker 卡死)
      const doc = await withTimeout(docPromise, docTimeout, 'PDF 元数据');
      const pageNum = parseInt(canvas.dataset.pageNum);
      if (!pageNum || pageNum < 1 || pageNum > doc.numPages) {
        throw new Error(`Invalid page num ${pageNum} (total ${doc.numPages})`);
      }
      const page = await withTimeout(doc.getPage(pageNum), 15000, `第 ${pageNum} 页拉取`);

      // 容器宽度(CSS 像素)
      const wrap = canvas.parentElement;
      const targetWidth = wrap.clientWidth || 540;

      // DPR 跨平台适配:Mac retina DPR=2,Windows 普通屏 DPR=1
      // Math.max(DPR, 2) × oversample(默认 2)→ Mac 渲 4x,Windows 渲 4x,跨平台一致
      const dpr = Math.max(window.devicePixelRatio || 1, 2);
      const baseVp = page.getViewport({ scale: 1 });
      const scale = (targetWidth / baseVp.width) * dpr * oversample;
      const vp = page.getViewport({ scale });

      // canvas 物理像素(高分辨率)+ CSS 像素(显示尺寸)
      canvas.width = vp.width;
      canvas.height = vp.height;
      canvas.style.width = targetWidth + 'px';
      canvas.style.height = (targetWidth * baseVp.height / baseVp.width) + 'px';

      const ctx = canvas.getContext('2d', { alpha: false });
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = 'high';

      // intent='print' 走 PDF.js 最高质量路径(更精的字形 hinting + 线宽控制)
      // 单页 render 超时 30s(防字形渲染死循环)
      await withTimeout(
        page.render({ canvasContext: ctx, viewport: vp, intent: 'print' }).promise,
        30000,
        `第 ${pageNum} 页渲染`
      );

      canvas.dataset.rendered = '1';
    } catch (e) {
      console.error('[pdf-renderer]', `page ${canvas.dataset.pageNum} render fail:`, e);
      canvas.dataset.rendered = '';
      // 单页失败:展示提示 + 保留滚动位置不影响其他页
      showPageError(canvas, e.message || '未知错误');
    }
  }

  const canvases = document.querySelectorAll('canvas.pdf-page');

  if (lazy && 'IntersectionObserver' in window) {
    // 懒加载:进入视口前 500px 才渲染,避免一次性渲所有页
    const io = new IntersectionObserver(entries => {
      for (const e of entries) {
        if (e.isIntersecting) renderCanvas(e.target);
      }
    }, { rootMargin: '500px' });
    canvases.forEach(c => io.observe(c));
  } else {
    // 立即渲染所有页(适合短文档或显式禁用 lazy)
    canvases.forEach(renderCanvas);
  }

  // 点击 canvas 弹放大 modal(可选)
  canvases.forEach(c => {
    c.addEventListener('click', () => {
      const url = c.toDataURL('image/png');
      const modal = document.getElementById('imgModal');
      if (modal) {
        modal.querySelector('img').src = url;
        modal.classList.add('show');
      }
    });
  });

  return docPromise;
}

// 便捷:auto-init from data-pdf-url attribute on body
if (document.body && document.body.dataset.pdfUrl) {
  initPdfRenderer({ pdfUrl: document.body.dataset.pdfUrl });
}
