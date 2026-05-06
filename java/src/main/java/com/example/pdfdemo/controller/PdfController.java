package com.example.pdfdemo.controller;

import org.springframework.core.io.Resource;
import org.springframework.core.io.ClassPathResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

/**
 * 服务原 PDF 文件 + HTTP Range request 支持
 *
 * 关键:Spring Boot 的 ResourceHttpRequestHandler 自动处理 Range header
 * 你不用写任何 Range 解析代码,直接返回 Resource 即可,Spring 自动响应 206 Partial Content。
 *
 * 即使是 ClassPathResource(打包在 jar 内)也能正确分块响应,
 * 因为 Spring 通过 Resource.contentLength() + getInputStream() 支持范围读取。
 */
@RestController
public class PdfController {

    @GetMapping(value = "/pdf/{name}", produces = MediaType.APPLICATION_PDF_VALUE)
    public ResponseEntity<Resource> serve(@PathVariable String name) {
        // 仅允许 .pdf 后缀,防路径注入
        if (!name.matches("[A-Za-z0-9_\\-\\.]+\\.pdf")) {
            return ResponseEntity.badRequest().build();
        }

        Resource pdf = new ClassPathResource("pdf/" + name);
        if (!pdf.exists()) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok()
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .header(HttpHeaders.CACHE_CONTROL, "public, max-age=3600")
                .body(pdf);
    }
}
