# launch.ps1 - Windows background start/stop for PDF Demo
# Usage:
#   .\launch.ps1                       start on default port 8092
#   .\launch.ps1 -Port 8093            start on custom port (PID/log files
#                                      become pdfdemo-8093.pid / .log so
#                                      multiple instances can coexist)
#   .\launch.ps1 -Stop                 stop the 8092 instance
#   .\launch.ps1 -Port 8093 -Stop      stop the 8093 instance
#   .\launch.ps1 -Status               show 8092 status
#   .\launch.ps1 -Port 8093 -Status    show 8093 status
#
# Prereq:
#   - pdfdemo.jar in same directory
#   - Java 17+ installed (java -version works)
#   - Windows Defender ExclusionPath added (otherwise startup is slow or fails)
#   - PowerShell ExecutionPolicy allows scripts:
#     Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#
# Note: kept ASCII-only on purpose -- Windows PowerShell 5.x parses .ps1
# files using the OS default codepage (GBK on zh-CN), and UTF-8 emoji/CJK
# would corrupt string literals and crash parsing.

param(
    [switch]$Stop,
    [switch]$Status,
    [int]$Port = 8092
)

$ErrorActionPreference = "Stop"
$JarPath = Join-Path $PSScriptRoot "pdfdemo.jar"

# When user keeps default port 8092, use legacy short filenames for back-compat;
# any non-default port gets per-port PID/log so multiple instances coexist.
if ($Port -eq 8092) {
    $LogPath = Join-Path $PSScriptRoot "pdfdemo.log"
    $PidFile = Join-Path $PSScriptRoot "pdfdemo.pid"
} else {
    $LogPath = Join-Path $PSScriptRoot "pdfdemo-${Port}.log"
    $PidFile = Join-Path $PSScriptRoot "pdfdemo-${Port}.pid"
}

function Get-DemoPid {
    if (Test-Path $PidFile) {
        $existingPid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($existingPid) {
            $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
            if ($proc) { return [int]$existingPid }
        }
    }
    return $null
}

if ($Status) {
    $existingPid = Get-DemoPid
    if ($existingPid) {
        $proc = Get-Process -Id $existingPid
        $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        Write-Host "[OK] Demo running -- PID $existingPid, mem ${memMB} MB" -ForegroundColor Green
        Write-Host "     Log: $LogPath"
        Write-Host "     Port: $Port"
        Write-Host "     URL: http://localhost:${Port}" -ForegroundColor Cyan
    } else {
        Write-Host "[--] Demo not running" -ForegroundColor Yellow
    }
    exit 0
}

if ($Stop) {
    $existingPid = Get-DemoPid
    if ($existingPid) {
        Write-Host "Stopping PID $existingPid ..." -ForegroundColor Yellow
        Stop-Process -Id $existingPid -Force
        Remove-Item $PidFile -ErrorAction SilentlyContinue
        Write-Host "[OK] Stopped" -ForegroundColor Green
    } else {
        Write-Host "[--] No running demo" -ForegroundColor Yellow
    }
    exit 0
}

# Start logic
$existingPid = Get-DemoPid
if ($existingPid) {
    Write-Host "[--] Demo already running -- PID $existingPid" -ForegroundColor Yellow
    Write-Host "     To stop: .\launch.ps1 -Stop"
    exit 1
}

if (-not (Test-Path $JarPath)) {
    Write-Host "[ERR] jar not found: $JarPath" -ForegroundColor Red
    Write-Host "      Build first: mvn clean package -DskipTests"
    Write-Host "      Or copy: copy ..\java\target\pdfdemo-1.0.0.jar pdfdemo.jar"
    exit 1
}

# Port-in-use check
$portInUse = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($portInUse) {
    $occupyPid = $portInUse[0].OwningProcess
    Write-Host "[ERR] Port $Port already in use by PID $occupyPid" -ForegroundColor Red
    Write-Host "      Inspect: Get-Process -Id $occupyPid"
    exit 1
}

Write-Host "Starting pdfdemo.jar in background ..." -ForegroundColor Cyan

# Use WMI/CIM to spawn a process that is NOT a child of the current
# PowerShell session. Without this, an SSH-launched run gets killed
# when the SSH connection ends (Windows OpenSSH puts the whole tree
# in a Job Object). Start-Process keeps the parent/child link too,
# so we use Win32_Process::Create which detaches cleanly.
$cmdLine = "java -Dserver.port=$Port -jar `"$JarPath`" > `"$LogPath`" 2> `"${LogPath}.err`""
$wrapped = "cmd.exe /c $cmdLine"
$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
    -Arguments @{ CommandLine = $wrapped; CurrentDirectory = $PSScriptRoot }

if ($result.ReturnValue -ne 0) {
    Write-Host "[ERR] Win32_Process Create failed (code $($result.ReturnValue))" -ForegroundColor Red
    exit 1
}

# $result.ProcessId is the cmd.exe wrapper PID, find the actual java child
Start-Sleep -Seconds 2
$javaProc = Get-CimInstance Win32_Process -Filter "ParentProcessId = $($result.ProcessId) AND Name = 'java.exe'" |
            Select-Object -First 1
if (-not $javaProc) {
    # cmd.exe may have exited; find the most recent java with our port marker
    $portMarker = "-Dserver.port=$Port"
    $javaProc = Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" |
                Where-Object { $_.CommandLine -like "*$portMarker*" -and $_.CommandLine -like "*pdfdemo.jar*" } |
                Sort-Object CreationDate -Descending | Select-Object -First 1
}

if (-not $javaProc) {
    Write-Host "[ERR] java process not found after spawn -- check log:" -ForegroundColor Red
    Write-Host "      Get-Content $LogPath -Tail 30"
    exit 1
}

$javaPid = $javaProc.ProcessId
$javaPid | Out-File -FilePath $PidFile -Encoding ASCII

# Wait 5s and verify still running
Start-Sleep -Seconds 5
$check = Get-Process -Id $javaPid -ErrorAction SilentlyContinue
if (-not $check) {
    Write-Host "[ERR] Process exited right after start -- check log:" -ForegroundColor Red
    Write-Host "      Get-Content $LogPath -Tail 30"
    Remove-Item $PidFile -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "[OK] PID $javaPid started" -ForegroundColor Green
Write-Host "     Log:    Get-Content $LogPath -Wait -Tail 30"
Write-Host "     Status: .\launch.ps1 -Status"
Write-Host "     Stop:   .\launch.ps1 -Stop"
Write-Host ""
Write-Host "Browser: http://localhost:${Port}" -ForegroundColor Cyan
