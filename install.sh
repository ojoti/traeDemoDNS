#!/usr/bin/env bash
set -e

# ============================================================
# DNS Panel 一键安装脚本 (Linux/macOS)
# 自助授权解析系统 (Go + React)
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

step() { echo -e "\n${CYAN}[*] $1${NC}"; }
ok()   { echo -e "${GREEN}[OK] $1${NC}"; }
warn() { echo -e "${YELLOW}[!] $1${NC}"; }
err()  { echo -e "${RED}[X] $1${NC}"; }

# 参数解析
MODE="auto"
CONFIG_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker)  MODE="docker"; shift ;;
        --local)   MODE="local"; shift ;;
        --auto)    MODE="auto"; shift ;;
        --config-only) CONFIG_ONLY=true; shift ;;
        --help|-h)
            echo "用法: ./install.sh [--docker|--local|--auto] [--config-only]"
            echo ""
            echo "  --docker       使用 Docker 模式（docker-compose 启动全部服务）"
            echo "  --local        使用本地模式（构建 Go + React，连接本地数据库）"
            echo "  --auto         自动检测环境选择模式（默认）"
            echo "  --config-only  仅生成配置文件不启动服务"
            exit 0 ;;
        *) err "未知参数: $1"; exit 1 ;;
    esac
done

echo -e "${CYAN}"
echo "============================================"
echo "   DNS Panel 一键安装脚本 v1.0"
echo "   自助授权解析系统 (Go + React)"
echo "============================================"
echo -e "${NC}"

# ============================================================
# 环境检测
# ============================================================
step "检测运行环境..."

has_cmd() { command -v "$1" &>/dev/null; }

HAS_DOCKER=$(has_cmd docker && echo "yes" || echo "no")
HAS_COMPOSE=$(has_cmd docker-compose && echo "yes" || echo "no")
if [ "$HAS_COMPOSE" = "no" ] && [ "$HAS_DOCKER" = "yes" ]; then
    docker compose version &>/dev/null && HAS_COMPOSE="yes"
fi
HAS_GO=$(has_cmd go && echo "yes" || echo "no")
HAS_NODE=$(has_cmd node && echo "yes" || echo "no")
HAS_NPM=$(has_cmd npm && echo "yes" || echo "no")
HAS_PSQL=$(has_cmd psql && echo "yes" || echo "no")

echo "  Docker:         $HAS_DOCKER"
echo "  Docker Compose: $HAS_COMPOSE"
echo "  Go:             $HAS_GO"
echo "  Node.js:        $HAS_NODE"
echo "  npm:            $HAS_NPM"
echo "  psql:           $HAS_PSQL"

# ============================================================
# 模式选择
# ============================================================
if [ "$MODE" = "auto" ]; then
    if [ "$HAS_DOCKER" = "yes" ] && [ "$HAS_COMPOSE" = "yes" ]; then
        MODE="docker"
        step "自动选择 Docker 模式"
    elif [ "$HAS_GO" = "yes" ] && [ "$HAS_NODE" = "yes" ]; then
        MODE="local"
        step "自动选择本地模式"
    else
        err "环境不满足要求，请安装以下任一组合："
        echo "  方案 A: Docker + Docker Compose"
        echo "  方案 B: Go 1.22+ + Node.js 18+"
        exit 1
    fi
fi

echo -e "\n已选择安装模式: $MODE"

# ============================================================
# 生成配置文件
# ============================================================
step "生成配置文件..."

generate_config() {
    local db_host="$1" db_port="$2" db_user="$3" db_pass="$4" db_name="$5"
    local redis_addr="$6" jwt_secret="$7"
    cat > "$PROJECT_ROOT/config.yaml" <<EOF
server:
  host: "0.0.0.0"
  port: 8080
  mode: "release"
database:
  host: "$db_host"
  port: $db_port
  user: "$db_user"
  password: "$db_pass"
  dbname: "$db_name"
  sslmode: "disable"
  max_open_conns: 25
  max_idle_conns: 10
redis:
  addr: "$redis_addr"
  password: ""
  db: 0
  pool_size: 10
auth:
  jwt_secret: "$jwt_secret"
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
EOF
}

JWT_SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)

if [ "$MODE" = "docker" ]; then
    generate_config "127.0.0.1" 5432 "dnspanel" "dnspanel" "dnspanel" "127.0.0.1:6379" "$JWT_SECRET"
    ok "配置文件已生成: config.yaml"
else
    ok "使用现有配置文件: config.yaml"
fi

if [ "$CONFIG_ONLY" = true ]; then
    echo -e "\n${YELLOW}仅生成配置，退出。${NC}"
    exit 0
fi

# ============================================================
# Docker 模式
# ============================================================
if [ "$MODE" = "docker" ]; then
    step "Docker 模式：启动全部服务..."

    cd "$PROJECT_ROOT/deployments"

    # 停止旧容器
    echo "  停止旧容器..."
    if has_cmd docker-compose; then
        docker-compose down 2>/dev/null || true
        docker-compose up -d --build
    else
        docker compose down 2>/dev/null || true
        docker compose up -d --build
    fi

    if [ $? -ne 0 ]; then
        err "Docker 启动失败"
        exit 1
    fi
    cd "$PROJECT_ROOT"

    # 等待 PostgreSQL
    step "等待 PostgreSQL 就绪..."
    for i in $(seq 1 30); do
        if docker exec dnspanel-postgres pg_isready -U dnspanel 2>/dev/null | grep -q "accepting"; then
            ok "PostgreSQL 已就绪"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""

    # 执行迁移
    step "执行数据库迁移..."
    for mig in 001_init.up.sql 002_seed_data.sql; do
        mig_path="$PROJECT_ROOT/migrations/$mig"
        if [ -f "$mig_path" ]; then
            docker exec -i dnspanel-postgres psql -U dnspanel -d dnspanel < "$mig_path" 2>/dev/null
            ok "迁移完成: $mig"
        fi
    done

    # 等待应用
    step "等待应用服务就绪..."
    for i in $(seq 1 30); do
        if curl -s http://localhost:8080/health 2>/dev/null | grep -q "ok"; then
            ok "DNS Panel 已就绪"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""

    echo -e "${GREEN}"
    echo "============================================"
    echo "   安装完成！"
    echo "============================================"
    echo "   访问地址:  http://localhost:8080"
    echo "   健康检查:  http://localhost:8080/health"
    echo ""
    echo "   默认管理员:"
    echo "     用户名: admin"
    echo "     密码:   admin123"
    echo ""
    echo "   管理命令:"
    echo "     停止: cd deployments; docker-compose down"
    echo "     日志: docker logs -f dnspanel-app"
    echo "     重启: cd deployments; docker-compose restart app"
    echo "============================================"
    echo -e "${NC}"
    exit 0
fi

# ============================================================
# 本地模式
# ============================================================
if [ "$MODE" = "local" ]; then
    # 检查依赖
    if [ "$HAS_GO" = "no" ]; then
        err "Go 未安装，请从 https://go.dev/dl/ 下载安装 Go 1.22+"
        exit 1
    fi
    if [ "$HAS_NODE" = "no" ] || [ "$HAS_NPM" = "no" ]; then
        err "Node.js 未安装，请从 https://nodejs.org/ 下载安装 Node.js 18+"
        exit 1
    fi

    # 交互式配置
    step "配置数据库..."
    read -p "  数据库地址 (默认 127.0.0.1): " DB_HOST
    DB_HOST=${DB_HOST:-127.0.0.1}
    read -p "  数据库端口 (默认 5432): " DB_PORT
    DB_PORT=${DB_PORT:-5432}
    read -p "  数据库用户 (默认 dnspanel): " DB_USER
    DB_USER=${DB_USER:-dnspanel}
    read -sp "  数据库密码 (默认 dnspanel): " DB_PASS
    DB_PASS=${DB_PASS:-dnspanel}
    echo ""
    read -p "  数据库名 (默认 dnspanel): " DB_NAME
    DB_NAME=${DB_NAME:-dnspanel}
    read -p "  Redis 地址 (默认 127.0.0.1:6379): " REDIS_ADDR
    REDIS_ADDR=${REDIS_ADDR:-127.0.0.1:6379}

    generate_config "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DB_NAME" "$REDIS_ADDR" "$JWT_SECRET"
    ok "配置文件已更新"

    # 尝试用 Docker 启动数据库
    if [ "$HAS_PSQL" = "no" ] && [ "$HAS_DOCKER" = "yes" ]; then
        warn "未检测到 psql，尝试用 Docker 启动 PostgreSQL + Redis..."
        docker run -d --name dnspanel-postgres \
            -e POSTGRES_USER="$DB_USER" \
            -e POSTGRES_PASSWORD="$DB_PASS" \
            -e POSTGRES_DB="$DB_NAME" \
            -p 5432:5432 postgres:15-alpine 2>/dev/null || true
        docker run -d --name dnspanel-redis -p 6379:6379 redis:7-alpine 2>/dev/null || true
        echo "  等待数据库启动..."
        sleep 5
    fi

    # 执行迁移
    step "执行数据库迁移..."
    if [ "$HAS_PSQL" = "yes" ]; then
        export PGPASSWORD="$DB_PASS"
        for mig in 001_init.up.sql 002_seed_data.sql; do
            mig_path="$PROJECT_ROOT/migrations/$mig"
            if [ -f "$mig_path" ]; then
                psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$mig_path" 2>&1 | grep -E "ERROR|CREATE|INSERT" || true
                ok "迁移完成: $mig"
            fi
        done
        unset PGPASSWORD
    elif [ "$HAS_DOCKER" = "yes" ]; then
        for mig in 001_init.up.sql 002_seed_data.sql; do
            mig_path="$PROJECT_ROOT/migrations/$mig"
            if [ -f "$mig_path" ]; then
                docker exec -i dnspanel-postgres psql -U "$DB_USER" -d "$DB_NAME" < "$mig_path" 2>/dev/null
                ok "迁移完成: $mig"
            fi
        done
    else
        warn "无法执行迁移（缺少 psql 和 Docker），请手动执行 migrations/ 目录下的 SQL"
    fi

    # 构建前端
    step "构建前端..."
    cd "$PROJECT_ROOT/web"
    npm install --silent 2>/dev/null
    ok "依赖安装完成"
    npm run build 2>/dev/null
    ok "前端构建完成"
    cd "$PROJECT_ROOT"

    # 构建后端
    step "构建后端..."
    go build -ldflags="-s -w" -o bin/server ./cmd/server
    ok "后端构建完成: bin/server"

    # 启动服务
    step "启动服务..."
    ./bin/server -config config.yaml &
    SERVER_PID=$!

    # 等待就绪
    for i in $(seq 1 15); do
        if curl -s http://localhost:8080/health 2>/dev/null | grep -q "ok"; then
            ok "DNS Panel 已就绪"
            break
        fi
        echo -n "."
        sleep 2
    done
    echo ""

    echo -e "${GREEN}"
    echo "============================================"
    echo "   安装完成！"
    echo "============================================"
    echo "   访问地址:  http://localhost:8080"
    echo "   健康检查:  http://localhost:8080/health"
    echo ""
    echo "   默认管理员:"
    echo "     用户名: admin"
    echo "     密码:   admin123"
    echo ""
    echo "   后台运行:"
    echo "     nohup ./bin/server -config config.yaml &"
    echo ""
    echo "   停止服务: kill $SERVER_PID"
    echo "============================================"
    echo -e "${NC}"
    exit 0
fi
