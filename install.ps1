<#
.SYNOPSIS
    DNS Panel 一键安装脚本 (Windows PowerShell)
.DESCRIPTION
    自动检测环境，支持两种安装模式：
    1. Docker 模式（推荐）：使用 docker-compose 启动 PostgreSQL + Redis + 应用
    2. 本地模式：构建 Go 后端 + React 前端，连接本地/远程数据库
.PARAMETER Mode
    docker | local | auto（默认 auto，自动检测）
.PARAMETER ConfigOnly
    仅生成配置文件不启动服务
.EXAMPLE
    .\install.ps1
    .\install.ps1 -Mode docker
    .\install.ps1 -Mode local
#>

param(
    [ValidateSet("auto", "docker", "local")]
    [string]$Mode = "auto",
    [switch]$ConfigOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$GoPath = $env:GOROOT
if (-not $GoPath -and (Test-Path "C:\Users\$env:USERNAME\sdk\go1.25.0\bin\go.exe")) {
    $GoPath = "C:\Users\$env:USERNAME\sdk\go1.25.0"
}

# ============================================================
# 工具函数
# ============================================================

function Write-Step { param([string]$msg) Write-Host "`n[*] $msg" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "[X] $msg" -ForegroundColor Red }

function Test-Command {
    param([string]$cmd)
    $null = Get-Command $cmd -ErrorAction SilentlyContinue
    return $?
}

function Test-GoInstalled {
    $goExe = if ($GoPath) { Join-Path $GoPath "bin\go.exe" } else { "go" }
    return (Test-Command "go") -or (Test-Path $goExe)
}

function Invoke-Go {
    param([string[]]$Args)
    $goExe = if ($GoPath) { Join-Path $GoPath "bin\go.exe" } else { "go" }
    & $goExe @Args
}

function Wait-Service {
    param([string]$url, [string]$name, [int]$timeout = 60)
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction SilentlyContinue
            if ($resp.StatusCode -eq 200) {
                Write-OK "$name 已就绪"
                return $true
            }
        } catch {}
        Start-Sleep -Seconds 2
        $elapsed += 2
        Write-Host "." -NoNewline
    }
    Write-Host ""
    return $false
}

# ============================================================
# 环境检测
# ============================================================

Write-Host @"
============================================
   DNS Panel 一键安装脚本 v1.0
   自助授权解析系统 (Go + React)
============================================
"@ -ForegroundColor White

Write-Step "检测运行环境..."

$hasDocker = Test-Command "docker"
$hasDockerCompose = Test-Command "docker-compose"
if (-not $hasDockerCompose -and $hasDocker) {
    $hasDockerCompose = (docker compose version 2>$null) -ne $null
}
$hasGo = Test-GoInstalled
$hasNode = Test-Command "node"
$hasNpm = Test-Command "npm"
$hasPsql = Test-Command "psql"

Write-Host "  Docker:        $(if ($hasDocker) { '已安装' } else { '未安装' })"
Write-Host "  Docker Compose: $(if ($hasDockerCompose) { '已安装' } else { '未安装' })"
Write-Host "  Go:             $(if ($hasGo) { '已安装' } else { '未安装' })"
Write-Host "  Node.js:        $(if ($hasNode) { '已安装' } else { '未安装' })"
Write-Host "  npm:            $(if ($hasNpm) { '已安装' } else { '未安装' })"
Write-Host "  psql:           $(if ($hasPsql) { '已安装' } else { '未安装' })"

# ============================================================
# 模式选择
# ============================================================

if ($Mode -eq "auto") {
    if ($hasDocker -and $hasDockerCompose) {
        $Mode = "docker"
        Write-Step "自动选择 Docker 模式"
    } elseif ($hasGo -and $hasNode -and $hasNpm) {
        $Mode = "local"
        Write-Step "自动选择本地模式"
    } else {
        Write-Err "环境不满足要求，请安装以下任一组合："
        Write-Host "  方案 A: Docker + Docker Compose"
        Write-Host "  方案 B: Go 1.22+ + Node.js 18+"
        exit 1
    }
}

Write-Host "`n已选择安装模式: $Mode" -ForegroundColor White

# ============================================================
# 生成配置文件
# ============================================================

Write-Step "生成配置文件..."

$configPath = Join-Path $ProjectRoot "config.yaml"
if (-not (Test-Path $configPath)) {
    Copy-Item (Join-Path $ProjectRoot "config.yaml") $configPath -ErrorAction SilentlyContinue
}

# 根据模式调整配置
if ($Mode -eq "docker") {
    # Docker 模式下数据库和 Redis 用容器名
    $configContent = @"
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"
database:
  host: "127.0.0.1"
  port: 5432
  user: "dnspanel"
  password: "dnspanel"
  dbname: "dnspanel"
  sslmode: "disable"
  max_open_conns: 25
  max_idle_conns: 10
redis:
  addr: "127.0.0.1:6379"
  password: ""
  db: 0
  pool_size: 10
auth:
  jwt_secret: "$(New-Guid)"
  jwt_ttl: 24h
  refresh_ttl: 168h
  issuer: "dns-panel"
plugins:
  dns:
    cloudflare:
      api_token: ""
    aliyun:
      access_key_id: ""
      access_key_secret: ""
    tencent:
      secret_id: ""
      secret_key: ""
    bind:
      server: ""
      key_name: ""
      key: ""
  notify:
    email:
      smtp_host: ""
      smtp_port: 465
      smtp_user: ""
      smtp_pass: ""
      from_name: "DNS Panel"
    sms:
      provider: "aliyun"
      access_key_id: ""
      access_key_secret: ""
      sign_name: ""
      template_code: ""
monitor:
  health_check_interval: 5m
  ssl_check_interval: 1h
  alert_cooldown: 30m
log:
  level: "info"
  format: "json"
"@
    $configContent | Out-File -FilePath $configPath -Encoding utf8 -NoNewline
    Write-OK "配置文件已生成: config.yaml"
} else {
    Write-OK "使用现有配置文件: config.yaml"
}

if ($ConfigOnly) {
    Write-Host "`n仅生成配置，退出。" -ForegroundColor Yellow
    exit 0
}

# ============================================================
# Docker 模式
# ============================================================

if ($Mode -eq "docker") {
    Write-Step "Docker 模式：启动全部服务..."

    Push-Location (Join-Path $ProjectRoot "deployments")

    # 停止旧容器
    Write-Host "  停止旧容器..."
    if ($hasDockerCompose -and (Get-Command "docker-compose" -ErrorAction SilentlyContinue)) {
        docker-compose down 2>$null | Out-Null
    } else {
        docker compose down 2>$null | Out-Null
    }

    # 构建并启动
    Write-Host "  构建并启动容器（首次可能需要几分钟）..."
    if ($hasDockerCompose -and (Get-Command "docker-compose" -ErrorAction SilentlyContinue)) {
        docker-compose up -d --build
        if ($LASTEXITCODE -ne 0) { Write-Err "docker-compose 启动失败"; Pop-Location; exit 1 }
    } else {
        docker compose up -d --build
        if ($LASTEXITCODE -ne 0) { Write-Err "docker compose 启动失败"; Pop-Location; exit 1 }
    }
    Pop-Location

    # 等待 PostgreSQL 就绪
    Write-Step "等待 PostgreSQL 就绪..."
    $pgReady = $false
    for ($i = 0; $i -lt 30; $i++) {
        $result = docker exec dnspanel-postgres pg_isready -U dnspanel 2>$null
        if ($result -match "accepting connections") {
            $pgReady = $true
            break
        }
        Start-Sleep -Seconds 2
        Write-Host "." -NoNewline
    }
    Write-Host ""
    if (-not $pgReady) {
        Write-Warn "PostgreSQL 启动超时，请手动检查"
    } else {
        Write-OK "PostgreSQL 已就绪"
    }

    # 执行迁移
    Write-Step "执行数据库迁移..."
    $migrations = @("001_init.up.sql", "002_seed_data.sql")
    foreach ($mig in $migrations) {
        $migPath = Join-Path $ProjectRoot "migrations\$mig"
        if (Test-Path $migPath) {
            Get-Content $migPath -Raw | docker exec -i dnspanel-postgres psql -U dnspanel -d dnspanel 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-OK "迁移完成: $mig"
            } else {
                Write-Warn "迁移跳过（可能已执行）: $mig"
            }
        }
    }

    # 等待应用就绪
    Write-Step "等待应用服务就绪..."
    if (Wait-Service "http://localhost:8080/health" "DNS Panel" 60) {
        Write-Host ""
        Write-Host @"
============================================
   安装完成！
============================================
   访问地址:  http://localhost:8080
   健康检查:  http://localhost:8080/health

   默认管理员:
     用户名: admin
     密码:   admin123

   管理命令:
     停止: cd deployments; docker-compose down
     日志: docker logs -f dnspanel-app
     重启: cd deployments; docker-compose restart app
============================================
"@ -ForegroundColor Green
    } else {
        Write-Warn "应用未就绪，请查看日志: docker logs dnspanel-app"
    }
    exit 0
}

# ============================================================
# 本地模式
# ============================================================

if ($Mode -eq "local") {
    # 检查依赖
    if (-not $hasGo) {
        Write-Err "Go 未安装，请从 https://go.dev/dl/ 下载安装 Go 1.22+"
        exit 1
    }
    if (-not $hasNode -or -not $hasNpm) {
        Write-Err "Node.js 未安装，请从 https://nodejs.org/ 下载安装 Node.js 18+"
        exit 1
    }

    # 检查数据库
    Write-Step "检查数据库连接..."
    $dbHost = Read-Host "  数据库地址 (默认 127.0.0.1)"
    if (-not $dbHost) { $dbHost = "127.0.0.1" }
    $dbPort = Read-Host "  数据库端口 (默认 5432)"
    if (-not $dbPort) { $dbPort = "5432" }
    $dbUser = Read-Host "  数据库用户 (默认 dnspanel)"
    if (-not $dbUser) { $dbUser = "dnspanel" }
    $dbPass = Read-Host "  数据库密码 (默认 dnspanel)" -AsSecureString
    $dbPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPass)
    )
    if (-not $dbPassPlain) { $dbPassPlain = "dnspanel" }
    $dbName = Read-Host "  数据库名 (默认 dnspanel)"
    if (-not $dbName) { $dbName = "dnspanel" }

    $redisHost = Read-Host "  Redis 地址 (默认 127.0.0.1:6379)"
    if (-not $redisHost) { $redisHost = "127.0.0.1:6379" }

    # 更新配置文件
    Write-Step "更新配置文件..."
    $config = Get-Content $configPath -Raw
    $config = $config -replace 'host: "127.0.0.1"', "host: `"$dbHost`"" -replace '(?ms)(database:.*?host: )"[^"]*"', "`${1}`"$dbHost`""
    # 简单替换：直接重写关键行
    $configLines = Get-Content $configPath
    $newLines = @()
    foreach ($line in $configLines) {
        switch -Wildcard ($line.Trim()) {
            "host: *" { if ($line -match "database") {} }
            default { $newLines += $line }
        }
    }
    # 直接用新值重写配置
    $configContent = @"
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"
database:
  host: "$dbHost"
  port: $dbPort
  user: "$dbUser"
  password: "$dbPassPlain"
  dbname: "$dbName"
  sslmode: "disable"
  max_open_conns: 25
  max_idle_conns: 10
redis:
  addr: "$redisHost"
  password: ""
  db: 0
  pool_size: 10
auth:
  jwt_secret: "$(New-Guid)"
  jwt_ttl: 24h
  refresh_ttl: 168h
  issuer: "dns-panel"
plugins:
  dns:
    cloudflare:
      api_token: ""
    aliyun:
      access_key_id: ""
      access_key_secret: ""
    tencent:
      secret_id: ""
      secret_key: ""
    bind:
      server: ""
      key_name: ""
      key: ""
  notify:
    email:
      smtp_host: ""
      smtp_port: 465
      smtp_user: ""
      smtp_pass: ""
      from_name: "DNS Panel"
    sms:
      provider: "aliyun"
      access_key_id: ""
      access_key_secret: ""
      sign_name: ""
      template_code: ""
monitor:
  health_check_interval: 5m
  ssl_check_interval: 1h
  alert_cooldown: 30m
log:
  level: "info"
  format: "text"
"@
    $configContent | Out-File -FilePath $configPath -Encoding utf8 -NoNewline
    Write-OK "配置文件已更新"

    # 尝试用 Docker 启动 PostgreSQL + Redis（如果没有本地数据库）
    if (-not $hasPsql -and $hasDocker) {
        Write-Warn "未检测到 psql 客户端，尝试用 Docker 启动 PostgreSQL + Redis..."
        docker run -d --name dnspanel-postgres -e POSTGRES_USER=$dbUser -e POSTGRES_PASSWORD=$dbPassPlain -e POSTGRES_DB=$dbName -p 5432:5432 postgres:15-alpine 2>$null
        docker run -d --name dnspanel-redis -p 6379:6379 redis:7-alpine 2>$null
        Write-Host "  等待数据库启动..."
        Start-Sleep -Seconds 5
    }

    # 执行迁移
    Write-Step "执行数据库迁移..."
    if ($hasPsql) {
        foreach ($mig in @("001_init.up.sql", "002_seed_data.sql")) {
            $migPath = Join-Path $ProjectRoot "migrations\$mig"
            if (Test-Path $migPath) {
                $env:PGPASSWORD = $dbPassPlain
                psql -h $dbHost -p $dbPort -U $dbUser -d $dbName -f $migPath 2>&1 | ForEach-Object {
                    if ($_ -match "ERROR") { Write-Warn $_ } else { Write-Host "  $_" -NoNewline }
                }
                Remove-Item Env:PGPASSWORD
                Write-OK "迁移完成: $mig"
            }
        }
    } elseif ($hasDocker) {
        foreach ($mig in @("001_init.up.sql", "002_seed_data.sql")) {
            $migPath = Join-Path $ProjectRoot "migrations\$mig"
            if (Test-Path $migPath) {
                Get-Content $migPath | docker exec -i dnspanel-postgres psql -U $dbUser -d $dbName 2>&1 | Out-Null
                Write-OK "迁移完成: $mig"
            }
        }
    } else {
        Write-Warn "无法执行迁移（缺少 psql 和 Docker），请手动执行 migrations/ 目录下的 SQL 文件"
    }

    # 构建前端
    Write-Step "构建前端..."
    Push-Location (Join-Path $ProjectRoot "web")
    npm install --silent 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err "npm install 失败"; Pop-Location; exit 1 }
    Write-OK "依赖安装完成"
    npm run build 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Err "前端构建失败"; Pop-Location; exit 1 }
    Write-OK "前端构建完成"
    Pop-Location

    # 构建后端
    Write-Step "构建后端..."
    Invoke-Go -Args @("build", "-ldflags=-s -w", "-o", "bin\server.exe", ".\cmd\server")
    if ($LASTEXITCODE -ne 0) { Write-Err "后端构建失败"; exit 1 }
    Write-OK "后端构建完成: bin\server.exe"

    # 启动服务
    Write-Step "启动服务..."
    $proc = Start-Process -FilePath ".\bin\server.exe" -ArgumentList "-config", "config.yaml" -PassThru -NoNewWindow

    if (Wait-Service "http://localhost:8080/health" "DNS Panel" 30) {
        Write-Host @"
============================================
   安装完成！
============================================
   访问地址:  http://localhost:8080
   健康检查:  http://localhost:8080/health

   默认管理员:
     用户名: admin
     密码:   admin123

   后台运行:
     .\bin\server.exe -config config.yaml

   停止服务: PID = $($proc.Id)
     Stop-Process -Id $($proc.Id)
============================================
"@ -ForegroundColor Green
    } else {
        Write-Warn "服务未就绪，请手动运行: .\bin\server.exe -config config.yaml"
    }
    exit 0
}
