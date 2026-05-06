<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\PdfController;

/*
|----------------------------------------------------------------------
| PDF.js demo — 仅 2 个路由
|----------------------------------------------------------------------
| 1. GET /        → 渲染 viewer.blade.php(canvas 占位 + 引入 PDF.js)
| 2. GET /pdf/{n} → serve 原 PDF + Range 支持(BinaryFileResponse 自带)
*/

Route::get('/', function () {
    return view('viewer', [
        'pdfUrl' => '/pdf/chuanmei_2026_02.pdf',
        'pdfName' => '中国传媒科技 2026 年第 2 期',
        'pageCount' => 164,
    ]);
});

Route::get('/pdf/{name}', [PdfController::class, 'serve'])
    ->where('name', '[A-Za-z0-9_\-\.]+\.pdf');
