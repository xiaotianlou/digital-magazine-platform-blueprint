<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

/**
 * 服务原 PDF 文件 + HTTP Range request 支持
 *
 * 关键:
 *   response()->file() 用 Symfony BinaryFileResponse,
 *   自动支持 Range header,响应 206 Partial Content。
 *   你不用写任何 Range 解析代码。
 */
class PdfController extends Controller
{
    public function serve(string $name, Request $request)
    {
        $path = public_path("pdf/{$name}");

        if (!file_exists($path)) {
            abort(404, "PDF not found: {$name}");
        }

        return response()->file($path, [
            'Content-Type' => 'application/pdf',
            'Accept-Ranges' => 'bytes',
            'Cache-Control' => 'public, max-age=3600',
            // 如果想强制下载用 'Content-Disposition' => 'attachment; ...'
            // 但 PDF.js 需要 inline,默认是 inline 不用设
        ]);
    }
}
