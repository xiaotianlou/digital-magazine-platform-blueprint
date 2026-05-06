# Java Spring Boot 3.4 demo

最小 Spring Boot 项目,演示 PDF.js 客户端矢量渲染。**仅 2 个 Controller** + 复用 viewer/ 静态资源。

## 文件清单

```
java/
├── pom.xml                                              # 仅 spring-boot-starter-web/thymeleaf
├── src/main/
│   ├── java/com/example/pdfdemo/
│   │   ├── PdfDemoApplication.java                      # @SpringBootApplication 入口
│   │   └── controller/
│   │       ├── ViewerController.java                    # GET /        → templates/viewer.html
│   │       └── PdfController.java                       # GET /pdf/{n} → 自动 Range 支持
│   └── resources/
│       ├── application.yml                              # port 8092 + thymeleaf cache off
│       ├── templates/viewer.html                        # Thymeleaf 模板(套 viewer/index.html)
│       ├── static/                                      # pdf-renderer.js + styles.css
│       └── pdf/chuanmei_2026_02.pdf                     # demo PDF(60 MB,164 页)
└── Dockerfile                                           # 多 stage build:maven build → JRE 跑
```

## 本地跑(无 docker)

需要本机有 Java 17+ 和 Maven 3.6+。

```bash
cd java/
mvn spring-boot:run
# 浏览器开 http://localhost:8092
```

或者打包成 jar:

```bash
mvn clean package -DskipTests
java -jar target/pdfdemo-1.0.0.jar
```

## Docker 跑

```bash
cd java/
docker build -t magazine-java-demo .
docker run -p 8092:8092 magazine-java-demo
```

## 验证

1. 浏览器看到 164 个 canvas 页占位
2. F12 → Network → `chuanmei_2026_02.pdf` 状态 = `206 Partial Content`
3. 滚动:新页 lazy 渲染
4. 点击任何 canvas:弹放大 modal

## Range 支持是怎么自动来的

```java
return ResponseEntity.ok()
    .header(HttpHeaders.ACCEPT_RANGES, "bytes")
    .body(pdf);  // pdf 是 Resource 类型(ClassPathResource)
```

返回 `Resource` 时,Spring 用 `ResourceHttpRequestHandler` 处理:
- 检查 request 有没有 `Range:` header
- 有 → 调 `Resource.contentLength()` 拿总长度,从 `getInputStream()` 读指定字节范围,响应 206
- 无 → 完整 200 响应

**你不写任何 Range 解析代码**。这是 Spring Boot 默认行为(自 5.0 起)。

## 关键代码 vs PHP 版对比

见 [`../php/README.md`](../php/README.md) 末尾的对比表。两边复杂度几乎相同,因为 demo 只是"serve PDF + 套 HTML"。
