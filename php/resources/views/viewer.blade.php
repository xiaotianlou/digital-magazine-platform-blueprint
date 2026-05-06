<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{{ $pdfName }} — Laravel Demo</title>
  <link rel="stylesheet" href="{{ asset('static/styles.css') }}">
</head>
<body data-pdf-url="{{ $pdfUrl }}">
  <div class="app">
    <header class="header">
      <div>
        <h1>📄 {{ $pdfName }}</h1>
        <div class="meta">{{ $pageCount }} 页 · Laravel 11 + PHP 8.3 · PDF.js 矢量渲染</div>
      </div>
      <div>
        <span class="badge">Laravel</span>
      </div>
    </header>

    <div class="intro">
      <strong>验证 Range request:</strong> F12 → Network → 看 PDF 请求是
      <code>206 Partial Content</code>(不是 200),只下载视口需要的几 KB。
      <br><br>
      <strong>验证省存储:</strong> 服务器 <code>du -sh public/pdf/</code> ≈ 60 MB,
      没有 <code>page_*.jpg</code>,完全不存预渲图。
    </div>

    <div class="pages">
      @for ($i = 1; $i <= $pageCount; $i++)
      <div class="page-block">
        <div class="label">第 {{ $i }} 页</div>
        <canvas class="pdf-page" data-page-num="{{ $i }}"></canvas>
      </div>
      @endfor
    </div>

    <footer class="footer">
      <p>Laravel + PDF.js demo · 不存 jpg,矢量精度</p>
      <p><a href="https://github.com/xiaotianlou/digital-magazine-platform-blueprint" target="_blank">仓库地址</a></p>
    </footer>
  </div>

  <div class="img-modal" id="imgModal" onclick="this.classList.remove('show')">
    <img alt="放大图">
  </div>

  <!-- PDF.js 库失败兜底:15 秒内还没渲染就显示 banner -->
  <script>
    setTimeout(() => {
      if (!document.querySelector('canvas.pdf-page[data-rendered="1"]')) {
        const banner = document.createElement('div');
        banner.style.cssText = 'position:fixed;top:0;left:0;right:0;background:#c0392b;color:#fff;padding:14px 22px;z-index:9999;font:14px sans-serif;text-align:center';
        banner.innerHTML = '⚠️ PDF.js 库加载慢或失败 · <a href="' + (document.body.dataset.pdfUrl || '#') + '" target="_blank" style="color:#fff;text-decoration:underline">下载原 PDF</a> · <a href="javascript:location.reload()" style="color:#fff;text-decoration:underline">刷新</a>';
        document.body.prepend(banner);
      }
    }, 15000);
  </script>
  <script type="module" src="{{ asset('static/pdf-renderer.js') }}"></script>
</body>
</html>
