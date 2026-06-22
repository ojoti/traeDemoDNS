.PHONY: all build run dev frontend tidy clean docker-up docker-down migrate install install-docker install-local

# Go 相关变量
GO=go
GOFLAGS=-ldflags="-s -w"
BINARY=bin/server
FRONTEND_DIR=web

# 默认目标
all: build

# 构建后端
build:
	$(GO) build $(GOFLAGS) -o $(BINARY) ./cmd/server

# 运行后端
run: build
	./$(BINARY) -config config.yaml

# 开发模式运行后端
dev:
	$(GO) run ./cmd/server -config config.yaml

# 前端开发
frontend:
	cd $(FRONTEND_DIR) && npm run dev

# 前端构建
frontend-build:
	cd $(FRONTEND_DIR) && npm run build

# 整理依赖
tidy:
	$(GO) mod tidy

# 清理
clean:
	rm -rf bin/ $(FRONTEND_DIR)/dist $(FRONTEND_DIR)/node_modules

# Docker 部署
docker-up:
	cd deployments && docker-compose up -d --build

docker-down:
	cd deployments && docker-compose down

# 数据库迁移
migrate:
	@echo "请确保 PostgreSQL 已启动，然后执行："
	@echo "  psql -h 127.0.0.1 -U dnspanel -d dnspanel -f migrations/001_init.up.sql"
	@echo "  psql -h 127.0.0.1 -U dnspanel -d dnspanel -f migrations/002_seed_data.sql"

# 生成 Swagger 文档（需要 swag 工具）
swagger:
	$(GO) install github.com/swaggo/swag/cmd/swag@latest
	swag init -g cmd/server/main.go -o docs

# 一键安装
install:
	@echo "请使用专用脚本："
	@echo "  Windows: powershell -ExecutionPolicy Bypass -File install.ps1"
	@echo "  Linux:   chmod +x install.sh && ./install.sh"

install-docker:
	@echo "Docker 模式安装..."
	@cd deployments && docker-compose up -d --build
	@echo "等待数据库就绪..."
	@sleep 5
	@docker exec -i dnspanel-postgres psql -U dnspanel -d dnspanel < migrations/001_init.up.sql 2>/dev/null || true
	@docker exec -i dnspanel-postgres psql -U dnspanel -d dnspanel < migrations/002_seed_data.sql 2>/dev/null || true
	@echo "安装完成！访问 http://localhost:8080 (admin / admin123)"

install-local:
	@echo "本地模式安装..."
	cd web && npm install && npm run build
	$(GO) build $(GOFLAGS) -o $(BINARY) ./cmd/server
	@echo "构建完成，运行: ./$(BINARY) -config config.yaml"

# 帮助
help:
	@echo "可用命令："
	@echo "  make install       - 一键安装（显示帮助）"
	@echo "  make install-docker - Docker 模式一键安装"
	@echo "  make install-local  - 本地模式一键安装"
	@echo "  make build         - 构建后端二进制"
	@echo "  make run           - 构建并运行后端"
	@echo "  make dev           - 开发模式运行后端（go run）"
	@echo "  make frontend      - 启动前端开发服务器"
	@echo "  make frontend-build - 构建前端"
	@echo "  make tidy          - 整理 Go 依赖"
	@echo "  make clean         - 清理构建产物"
	@echo "  make docker-up     - Docker Compose 启动全部服务"
	@echo "  make docker-down   - 停止 Docker 服务"
	@echo "  make migrate       - 显示数据库迁移命令"
