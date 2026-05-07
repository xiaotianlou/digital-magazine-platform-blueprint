# launch.ps1 — Windows 后台启动 / 停止 PDF Demo
#
# 用法:
#   .\launch.ps1          启动(后台 + 日志写到 pdfdemo.log)
#   .\launch.ps1 -Stop    停止
#   .\launch.ps1 -Status  看进程状态
#
# 前置:
#   - 当前目录有 pdfdemo.jar
#   - Java 17+ 已装 (java -version 能跑)
#   - 已加 Windows Defender ExclusionPath(否则启动巨慢或失败)
#   - 防火墙开了 8092 入站

param(
    [switch]$Stop,
    [switch]$Status
)

$ErrorActionPreference = "Stop"
$JarPath = Join-Path $PSScriptRoot "pdfdemo.jar"
$LogPath = Join-Path $PSScriptRoot "pdfdemo.log"
$PidFile = Join-Path $PSScriptRoot "pdfdemo.pid"
$Port = 8092

function Get-DemoPid {
    if (Test-Path $PidFile) {
        $existingPid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($existingPid) {
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) { return $existingPid }
        }
    }
    return $null
}

if ($Status) {
    $existingPid = Get-DemoPid
    if ($existingPid) {
        $proc = Get-Process -Id $existingPid
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        Write-Host "✅ Demo 运行中 — PID $existingPid, 内存 ${memMB} MB" -ForegroundColor Green
        Write-Host "   日志: $LogPath"
        Write-Host "   端口: $Port"
        $tsIp = (tailscale ip -4 2>$null) -split "`n" | Select-Object -First 1
        if ($tsIp) {
            Write-Host "   Tailscale URL: http://${tsIp}:${Port}" -ForegroundColor Cyan
        }
    } else {
        Write-Host "❌ Demo 未运行" -ForegroundColor Yellow
    }
    exit 0
}

if ($Stop) {
    $existingPid = Get-DemoPid
    if ($existingPid) {
        Write-Host "停止 PID $existingPid ..." -ForegroundColor Yellow
        Stop-Process -Id $existingPid -Force
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        Write-Host "✅ 已停止" -ForegroundColor Green
    } else {
        Write-Host "⚠️  没有运行中的 demo" -ForegroundColor Yellow
    }
    exit 0
}

# 启动逻辑
$existingPid = Get-DemoPid
if ($existingPid) {
    Write-Host "⚠️  Demo 已在运行 — PID $existingPid" -ForegroundColor Yellow
    Write-Host "    停止用: .\launch.ps1 -Stop"
    exit 1
}

if (-not (Test-Path $JarPath)) {
    Write-Host "❌ 找不到 jar: $JarPath" -ForegroundColor Red
    Write-Host "   先运行: mvn clean package 或 scp 上传 jar"
    exit 1
}

# 端口占用检查
$portInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
if ($portInUse) {
    $occupyPid = $portInUse[0].OwningProcess
    Write-Host "❌ 端口 $Port 已被 PID $occupyPid 占用" -ForegroundColor Red
    Write-Host "   查看: Get-Process -Id $occupyPid"
    exit 1
}

Write-Host "启动 pdfdemo.jar 后台进程..." -ForegroundColor Cyan
$proc = Start-Process -FilePath "java" `
    -ArgumentList "-jar", $JarPath `
    -RedirectStandardOutput $LogPath `
    -RedirectStandardError "${LogPath}.err" `
    -WorkingDirectory $PSScriptRoot `
    -WindowStyle Hidden `
    -PassThru

$proc.Id | Out-File -FilePath $PidFile -Encoding ASCII

# 等 5 秒看是否健康启动
Start-Sleep -Seconds 5
$check = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
if (-not $check) {
    Write-Host "❌ 进程启动后立刻退出 — 看日志:" -ForegroundColor Red
    Write-Host "   Get-Content $LogPath -Tail 30"
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "✅ PID $($proc.Id) 已启动" -ForegroundColor Green
Write-Host "   日志: Get-Content $LogPath -Wait -Tail 30"
Write-Host "   状态: .\launch.ps1 -Status"
Write-Host "   停止: .\launch.ps1 -Stop"

$tsIp = (tailscale ip -4 2>$null) -split "`n" | Select-Object -First 1
if ($tsIp) {
    Write-Host ""
    Write-Host "🌐 同事访问:http://${tsIp}:${Port}" -ForegroundColor Cyan
}
