# 🇨🇳 国内本地部署 — Windows + Tailscale(给同事低延迟看 demo)

> **背景**:159.203.0.28 是 DigitalOcean 美西节点,中国访问 240ms+,首次加载 PDF.js 库约 30 秒。
> **方案**:把 Spring Boot demo 部署到家里 / 公司内网的 Windows 机器,通过 Tailscale 让同事直连,延迟 < 30ms。

本目录记录的是 **lxf** 这台 Windows 内网机的部署流程,但流程通用 — 任何能跑 Java 17 的 Windows 机器都适用。

---

## 部署拓扑

```
        ┌─── 同事电脑(Tailscale 客户端)───┐
        │   浏览器 → http://100.126.52.49:8092 │
        └────────────────┬─────────────────────┘
                         │ Tailscale Mesh VPN
                         │ (端到端加密,P2P 直连)
                         ▼
        ┌─── lxf Windows 机 ────────────────┐
        │   Tailscale IP: 100.126.52.49     │
        │   局域网 IP: 192.168.x.x          │
        │   Java 17 + Spring Boot pdfdemo   │
        │   端口 8092                        │
        └────────────────────────────────────┘
```

**为什么用 Tailscale 不用公网 IP**:同事不一定在同一个局域网,公网 IP 又涉及备案和路由器端口转发,Tailscale 给每台机器一个稳定虚拟 IP,装客户端登录后即可访问,零运维。

---

## 一次性环境准备(在 Windows 机上做一次)

### 1. 装 Java 17+

下载 [Eclipse Temurin 17 LTS](https://adoptium.net/temurin/releases/?version=17),选 Windows MSI Installer 一路下一步。
验证:
```powershell
java -version
# openjdk version "17.x.x"
```

### 2. 装 Tailscale

1. 下载 [Tailscale Windows 客户端](https://tailscale.com/download/windows)
2. 安装后用 GitHub / Google / Microsoft 账号登录
3. 同事的电脑也装上,登录**同一个**账号(或同一个 tailnet)
4. 在 [admin.tailscale.com](https://login.tailscale.com/admin/machines) 看到本机的 100.x.x.x IP

### 3. 加 Windows Defender 排除

⚠️ **关键坑**:Windows Defender 实时扫描会锁住 jar 文件,导致 `Unable to access jarfile` 错误。

以**管理员**身份开 PowerShell:
```powershell
Add-MpPreference -ExclusionPath "C:\Users\admin1"
# 或更精确:
# Add-MpPreference -ExclusionPath "C:\Users\admin1\pdfdemo"
```

验证排除生效:
```powershell
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
```

### 4. 开 Windows 防火墙端口 8092

管理员 PowerShell:
```powershell
New-NetFirewallRule -DisplayName "PDF Demo 8092" `
  -Direction Inbound -Protocol TCP -LocalPort 8092 -Action Allow
```

---

## 部署 jar(每次更新代码做)

### 选项 A:从 Mac/Linux 编译 → SCP 到 Windows

**前提**:Windows 装了 OpenSSH Server(Win10/11 自带,启用方式见下)。

```bash
# 1. 在 Mac/Linux 编译
cd digital-magazine-platform-blueprint/java
mvn clean package -DskipTests
# 产出 target/pdfdemo-1.0.0.jar (~55 MB)

# 2. SCP 到 lxf(假设 Tailscale 已通,主机别名 lxf)
scp target/pdfdemo-1.0.0.jar lxf:C:/Users/admin1/pdfdemo/pdfdemo.jar
```

⚠️ Tailscale SCP 速度约 1 MB/s 起,55 MB 约需 1–2 分钟。

### 选项 B:直接在 Windows 上编译(更快,推荐)

```powershell
# 1. 装 Maven(如未装)
winget install Apache.Maven

# 2. clone + build
cd C:\Users\admin1
git clone https://github.com/xiaotianlou/digital-magazine-platform-blueprint
cd digital-magazine-platform-blueprint\java
mvn clean package -DskipTests

# 3. jar 在 target\pdfdemo-1.0.0.jar
copy target\pdfdemo-1.0.0.jar C:\Users\admin1\pdfdemo\pdfdemo.jar
```

### 启用 Windows OpenSSH Server(选项 A 需要)

管理员 PowerShell:
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" `
  -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
```

把 Mac 的 `~/.ssh/id_rsa.pub` 加到 Windows 的 `C:\Users\admin1\.ssh\authorized_keys`(注意权限,见 [微软文档](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement))。

`~/.ssh/config` 加:
```
Host lxf
  HostName 100.126.52.49
  User admin1
  IdentityFile ~/.ssh/id_rsa
```

---

## 启动 demo

### 一次性手动启动(测试用)

```powershell
cd C:\Users\admin1\pdfdemo
java -jar pdfdemo.jar
# Spring Boot 启动后,看到 "Started PdfDemoApplication"
# 浏览器开 http://localhost:8092 自测
# 同事电脑开 http://100.126.52.49:8092
```

### 用 launch.ps1 启动(后台 + 日志)

本目录提供的 [`launch.ps1`](./launch.ps1) 把 Java 进程放后台,日志写到 `pdfdemo.log`,适合让 demo 长期跑着。

```powershell
cd C:\Users\admin1\pdfdemo
.\launch.ps1
# 看到 "PID xxxx 已启动"
# tail 日志:Get-Content pdfdemo.log -Wait -Tail 30
```

停止:
```powershell
.\launch.ps1 -Stop
```

### 开机自启(可选)

把 launch.ps1 注册成 Task Scheduler 任务,触发器选"用户登录时"。或更简单:把 PowerShell 快捷方式放到 `shell:startup` 目录,参数填启动脚本路径。

---

## 验证可访问

**本机测试**(在 lxf 上):
```powershell
curl http://localhost:8092/  # 应返回 HTML
```

**同事电脑**(已装 Tailscale):
- 浏览器开 http://100.126.52.49:8092
- F12 → Network 看 PDF 是 206 Partial Content
- 翻几页,看 canvas 渲染流畅

**首次访问预期**:< 5 秒看到第一页(同 tailnet 内,延迟 ~30ms)。
**对比**:159.203.0.28:8092 国内首次访问需 ~30 秒(海外 + jsdelivr 慢)。

---

## 常见问题

| 症状 | 原因 | 解决 |
|---|---|---|
| `Unable to access jarfile pdfdemo.jar` | Windows Defender 实时扫描锁文件 | `Add-MpPreference -ExclusionPath C:\Users\admin1` |
| 同事访问超时 | Tailscale 没装 / 没登同账号 / 防火墙没开 8092 | 三件套依次排查 |
| Java 启动后立刻退出 | 端口 8092 已占用 | `netstat -ano | findstr :8092` 看占用 PID,kill 掉 |
| 同事页面白屏只看到标题 | jsdelivr CDN 国内被墙 | 已修:本 demo 自带 PDF.js 库本地 host,不依赖 CDN |
| jar 启动巨慢(60s+)| Defender 扫整个 jar 内 5000+ class | 同上加 ExclusionPath |
| 重启后 Tailscale IP 不一样 | 不会 — Tailscale IP 是机器绑定,稳定不变 | — |

---

## 维护

| 操作 | 命令 |
|---|---|
| 看运行状态 | `Get-Process java` |
| 看实时日志 | `Get-Content C:\Users\admin1\pdfdemo\pdfdemo.log -Wait -Tail 30` |
| 重启 | `.\launch.ps1 -Stop; .\launch.ps1` |
| 更新代码后重新部署 | `git pull; mvn clean package -DskipTests; copy /Y target\pdfdemo-1.0.0.jar pdfdemo.jar; .\launch.ps1 -Stop; .\launch.ps1` |
| 看 Tailscale IP | `tailscale ip -4` |

---

## 文件清单

```
deploy-lxf-windows-local/
├── README.md       本文件 — 完整部署流程
└── launch.ps1      Windows 后台启动 / 停止脚本
```

> demo 源码在仓库根的 [`java/`](../java/) 目录。本目录只是部署脚本/文档,不重复源码。
