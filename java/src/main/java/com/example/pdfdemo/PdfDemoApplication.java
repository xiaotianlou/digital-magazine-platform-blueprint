package com.example.pdfdemo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * PDF.js 客户端矢量渲染 demo (Spring Boot 3.4)
 *
 * 启动: mvn spring-boot:run 或 java -jar target/pdfdemo-1.0.0.jar
 * 端口: 8092 (见 application.yml)
 */
@SpringBootApplication
public class PdfDemoApplication {
    public static void main(String[] args) {
        SpringApplication.run(PdfDemoApplication.class, args);
    }
}
