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
 */

import * as pdfjs from 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs';
pdfjs.GlobalWorkerOptions.workerSrc =
  'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs';

export async function initPdfRenderer({ pdfUrl, lazy = true, oversample = 2 } = {}) {
  if (!pdfUrl) throw new Error('pdfUrl required');

  // 拉 PDF 元数据 + 准备 doc 对象(Range request 自动开启)
  const docPromise = pdfjs.getDocument({
    url: pdfUrl,
    rangeChunkSize: 65536,    // 每次 Range 拉 64 KB
    disableStream: false,     // 启用 streaming
  }).promise;

  // 单页渲染
  async function renderCanvas(canvas) {
    if (canvas.dataset.rendered) return;
    canvas.dataset.rendered = 'pending';
    try {
      const doc = await docPromise;
      const pageNum = parseInt(canvas.dataset.pageNum);
      if (!pageNum || pageNum < 1 || pageNum > doc.numPages) {
        throw new Error(`Invalid page num ${pageNum} (total ${doc.numPages})`);
      }
      const page = await doc.getPage(pageNum);

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
      await page.render({
        canvasContext: ctx,
        viewport: vp,
        intent: 'print',
      }).promise;

      canvas.dataset.rendered = '1';
    } catch (e) {
      console.error('[pdf-renderer]', `page ${canvas.dataset.pageNum} render fail:`, e);
      canvas.dataset.rendered = '';
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
