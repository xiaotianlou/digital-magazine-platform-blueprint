<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * 服务原 PDF 文件 + 手工实现 HTTP Range request
 *
 * ⚠️ 注意:用 `php artisan serve` 的 PHP 内置 dev server **不支持 Range header**
 *    (已知 PHP built-in server 限制)。生产环境用 nginx + php-fpm 时,
 *    `response()->file()` 自动支持 Range,这段手工解析其实可以省掉。
 *    但为了让 demo 在 dev server 也能验证 Range,我们手工实现。
 *
 * Range header 解析逻辑(精简版):
 *   1. 读 Range: bytes=<start>-<end>
 *   2. 算字节范围
 *   3. 用 fopen + fseek + fread 流式输出
 *   4. 响应 206 + Content-Range header
 */
class PdfController extends Controller
{
    public function serve(string $name, Request $request)
    {
        $path = public_path("pdf/{$name}");
        if (!file_exists($path)) {
            abort(404, "PDF not found: {$name}");
        }

        $size = filesize($path);
        $rangeHeader = $request->header('Range');

        // 无 Range → 完整 200 响应
        if (!$rangeHeader || !preg_match('/bytes=(\d+)-(\d*)/', $rangeHeader, $m)) {
            return response()->stream(function () use ($path) {
                readfile($path);
            }, 200, [
                'Content-Type' => 'application/pdf',
                'Content-Length' => $size,
                'Accept-Ranges' => 'bytes',
                'Cache-Control' => 'public, max-age=3600',
            ]);
        }

        // 解析 Range
        $start = (int) $m[1];
        $end = $m[2] === '' ? $size - 1 : (int) $m[2];
        $end = min($end, $size - 1);
        if ($start > $end) {
            return response('', 416, ['Content-Range' => "bytes */$size"]);
        }
        $length = $end - $start + 1;

        // 206 Partial Content 流式响应
        return response()->stream(function () use ($path, $start, $length) {
            $fh = fopen($path, 'rb');
            fseek($fh, $start);
            $remaining = $length;
            while ($remaining > 0 && !feof($fh)) {
                $chunk = fread($fh, min(8192, $remaining));
                echo $chunk;
                $remaining -= strlen($chunk);
                @ob_flush();
                @flush();
            }
            fclose($fh);
        }, 206, [
            'Content-Type' => 'application/pdf',
            'Content-Length' => $length,
            'Content-Range' => "bytes {$start}-{$end}/{$size}",
            'Accept-Ranges' => 'bytes',
            'Cache-Control' => 'public, max-age=3600',
        ]);
    }
}
