# Windows 本地启动 demo

> 在自己 Windows 机器上跑 Spring Boot demo,自己浏览器开 `http://localhost:8092` 看效果。
> 不涉及任何远程访问 / 内网穿透,纯单机本地。

---

## 前置 — 装一次

### 1. Java 17+

下载 [Eclipse Temurin 17 LTS](https://adoptium.net/temurin/releases/?version=17),Windows MSI 一路下一步。

```powershell
java -version
# openjdk version "17.x.x" 即可
```

### 2. Maven(编译用)

```powershell
winget install Apache.Maven
mvn -version
```

### 3. ⚠️ Windows Defender 加排除路径

**关键坑**:Defender 实时扫描会锁住 jar 内的 class,导致 `Unable to access jarfile` 错误,或启动巨慢(60s+)。

**管理员** PowerShell:
```powershell
Add-MpPreference -ExclusionPath "C:\Users\$env:USERNAME\pdfdemo"
```

---

## 编译 + 启动

```powershell
# 拉代码
cd C:\Users\$env:USERNAME
git clone https://github.com/xiaotianlou/digital-magazine-platform-blueprint
cd digital-magazine-platform-blueprint\java

# 编译(产出 target\pdfdemo-1.0.0.jar,约 55 MB)
mvn clean package -DskipTests

# 启动(前台)
java -jar target\pdfdemo-1.0.0.jar
# 看到 "Started PdfDemoApplication" 即成功

# 浏览器开 http://localhost:8092
```

Ctrl+C 停止。

---

## 后台启动(用 launch.ps1)

不想前台占着 PowerShell 窗口,可用本目录提供的 [`launch.ps1`](./launch.ps1):

```powershell
# 把 jar 放到 launch.ps1 同目录,改名为 pdfdemo.jar
copy ..\java\target\pdfdemo-1.0.0.jar pdfdemo.jar

# 启动
.\launch.ps1
# 看状态
.\launch.ps1 -Status
# 看日志
Get-Content pdfdemo.log -Wait -Tail 30
# 停止
.\launch.ps1 -Stop
```

`launch.ps1` 做了:端口占用检查、PID 管理、日志重定向、启动 5 秒后健康检查。

---

## PHP demo 也想本地跑?

PHP demo 推荐用 Docker:
```powershell
cd ..\php
docker build -t magazine-php-demo .
docker run -p 8091:80 magazine-php-demo
# 浏览器开 http://localhost:8091
```

裸装 PHP 8.3 + nginx + php-fpm 在 Windows 上配置较麻烦,Docker 一句话搞定。

---

## 常见问题

| 症状 | 解决 |
|---|---|
| `Unable to access jarfile pdfdemo.jar` | Defender 锁文件,见上面的 ExclusionPath |
| 启动 60 秒还没响应 | 同上 — Defender 在扫 5000+ class |
| 端口 8092 已占用 | `netstat -ano \| findstr :8092` 找占用 PID,`taskkill /PID xxx /F` |
| 浏览器打不开 localhost:8092 | 看启动日志有没有 `Started PdfDemoApplication`;没有就是 jar 启动失败 |
| 翻页卡顿 | 单机本地不应该卡;若卡看 F12 Console 有无 PDF.js 报错 |

---

## 文件清单

```
deploy-windows-local/
├── README.md       本文档
└── launch.ps1      可选的后台启动 / 停止脚本
```

> demo 源码在 [`../java/`](../java/),本目录只是部署辅助。
