package com.example.pdfdemo.controller;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * 渲染 viewer HTML 模板。
 * 单一路由 GET / → templates/viewer.html
 */
@Controller
public class ViewerController {

    @GetMapping("/")
    public String viewer(Model model) {
        model.addAttribute("pdfUrl", "/pdf/chuanmei_2026_02.pdf");
        model.addAttribute("pdfName", "中国传媒科技 2026 年第 2 期");
        model.addAttribute("pageCount", 164);
        return "viewer";
    }
}
