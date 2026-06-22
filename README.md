# 安装指南

本文档提供两种安装方式：Docker 一键部署（推荐）和本地源码编译安装。根据你的环境条件选择适合的方式。

---

## 环境要求

| 组件 | 版本要求 | 说明 |
|------|----------|------|
| Go | >= 1.21 | 后端编译 |
| Node.js | >= 18 | 前端构建 |
| PostgreSQL | >= 14 | 主数据库 |
| Redis | >= 6 | 缓存与会话 |
| Docker | >= 20.10 | Docker 模式必需 |
| Docker Compose | >= 2.0 | Docker 模式必需 |

---

## 方式一：Docker 一键部署（推荐）

当系统检测到已安装 Docker 时，优先使用此模式。全程自动化，无需手动配置数据库或编译代码。

### 1. 克隆仓库

```bash
git clone https://github.com/ojoti/traeDemoDNS.git
cd traeDemoDNS
```

### 2. 启动服务

```bash
docker-compose -f deployments/docker-compose.yml up -d
```

部署脚本将按以下顺序自动执行：

1. **启动基础设施** —— 拉取并运行 PostgreSQL 和 Redis 容器
2. **等待数据库就绪** —— 自动检测 PostgreSQL 服务可用性，最多重试 30 次
3. **执行数据库迁移** —— 运行 `migrations/` 目录下的所有 schema 和种子数据脚本
4. **构建应用镜像** —— 编译 Go 后端与 React 前端，打包为 Docker 镜像
5. **启动应用容器** —— 运行主服务，自动连接数据库与缓存
6. **健康检查** —— 确认 API 接口响应正常

### 3. 访问系统

部署完成后，终端将输出以下信息：

```
=====================================
  自助授权解析系统已启动
=====================================
访问地址: http://localhost:8080
管理后台: http://localhost:8080/admin

默认管理员账号:
  用户名: admin
  密码:   admin123

重要提示: 生产环境请务必修改默认密码
=====================================
```

### Docker 模式目录挂载

| 宿主机路径 | 容器路径 | 用途 |
|-----------|----------|------|
| `./data/postgres` | `/var/lib/postgresql/data` | 数据库持久化 |
| `./data/redis` | `/data` | 缓存持久化 |
| `./config.yaml` | `/app/config.yaml` | 配置文件 |
| `./logs` | `/app/logs` | 应用日志 |

---

## 方式二：本地源码编译安装

适用于无 Docker 环境或需要二次开发的场景。

### 1. 克隆仓库

```bash
git clone https://github.com/ojoti/traeDemoDNS.git
cd traeDemoDNS
```

### 2. 配置数据库连接

运行交互式配置脚本：

```bash
make config
```

脚本将提示输入以下信息：

```
请输入 PostgreSQL 主机地址 [localhost]: 
请输入 PostgreSQL 端口 [5432]: 
请输入 PostgreSQL 数据库名 [auth_resolver]: 
请输入 PostgreSQL 用户名 [postgres]: 
请输入 PostgreSQL 密码: 
请输入 Redis 主机地址 [localhost]: 
请输入 Redis 端口 [6379]: 
请输入 Redis 密码 [无]: 
```

配置完成后，自动生成 `config.yaml`，包含随机生成的 JWT 密钥：

```yaml
app:
  name: "自助授权解析系统"
  port: 8080
  mode: "release"

database:
  host: "localhost"
  port: 5432
  name: "auth_resolver"
  user: "postgres"
  password: "your-password"
  ssl_mode: "disable"
  max_open_conns: 25
  max_idle_conns: 5

redis:
  host: "localhost"
  port: 6379
  password: ""
  db: 0

jwt:
  secret: "auto-generated-random-key"
  access_token_ttl: 3600
  refresh_token_ttl: 604800
```

### 3. 数据库准备

#### 选项 A：本地 PostgreSQL

确保本地已安装 PostgreSQL 并创建数据库：

```bash
createdb auth_resolver
```

#### 选项 B：Docker 启动数据库（无本地 psql 时）

若本地未安装 PostgreSQL 但有 Docker，脚本自动执行：

```bash
docker run -d \
  --name auth-postgres \
  -e POSTGRES_DB=auth_resolver \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:15-alpine

docker run -d \
  --name auth-redis \
  -p 6379:6379 \
  redis:7-alpine
```

### 4. 构建前端

```bash
cd web
npm install
npm run build
```

构建产物输出至 `web/dist/`，由后端服务静态托管。

### 5. 构建后端

```bash
cd ..
go mod download
go build -o bin/server cmd/server/main.go
```

### 6. 执行数据库迁移

```bash
make migrate-up
```

或手动执行：

```bash
psql -U postgres -d auth_resolver -f migrations/001_schema.sql
psql -U postgres -d auth_resolver -f migrations/002_seed.sql
```

### 7. 启动服务

```bash
./bin/server
```

服务启动后将输出：

```
[GIN] 2026/06/22 - 10:00:00 | 服务启动于 :8080
[GIN] 2026/06/22 - 10:00:00 | 数据库连接成功
[GIN] 2026/06/22 - 10:00:00 | Redis 连接成功
[GIN] 2026/06/22 - 10:00:00 | 管理员账号已初始化: admin / admin123
```

---

## 安装后验证

### 检查服务状态

```bash
curl http://localhost:8080/api/health
```

预期响应：

```json
{
  "status": "ok",
  "database": "connected",
  "redis": "connected",
  "version": "3.0.0"
}
```

### 登录验证

1. 打开浏览器访问 `http://localhost:8080`
2. 使用默认管理员账号登录：
   - 用户名：`admin`
   - 密码：`admin123`
3. 登录成功后建议立即修改密码

---

## 常见问题

### Docker 模式

**Q: 数据库启动慢导致迁移失败？**

A: docker-compose 已配置 `depends_on` 和健康检查，自动等待数据库就绪。若仍失败，手动重试：

```bash
docker-compose -f deployments/docker-compose.yml restart app
```

**Q: 如何查看日志？**

```bash
docker-compose -f deployments/docker-compose.yml logs -f app
```

### 本地模式

**Q: 前端构建内存不足？**

```bash
export NODE_OPTIONS="--max-old-space-size=4096"
npm run build
```

**Q: Go 依赖下载慢？**

```bash
go env -w GOPROXY=https://goproxy.cn,direct
go mod download
```

**Q: 数据库连接失败？**

检查 `config.yaml` 中的连接信息，确认 PostgreSQL 服务已启动且防火墙未拦截端口。

---

## 生产环境建议

1. **修改默认密码** —— 首次登录后立即修改 `admin` 账号密码
2. **启用 HTTPS** —— 配置反向代理（Nginx/Caddy）并启用 TLS
3. **数据库备份** —— 定期备份 PostgreSQL 数据目录
4. **JWT 密钥** —— 生产环境使用强随机字符串替换默认密钥
5. **日志轮转** —— 配置 `logrotate` 避免日志文件无限增长
6. **资源限制** —— Docker 模式建议为容器设置 CPU/内存限制

---

## 目录速查

| 路径 | 内容 |
|------|------|
| `cmd/server/` | 主程序入口 |
| `internal/` | 核心业务模块 |
| `plugins/` | DNS 提供商与通知插件 |
| `web/` | React 前端源码 |
| `migrations/` | 数据库迁移脚本 |
| `deployments/` | Docker 与 K8s 部署配置 |
| `sdk/` | 多语言 SDK 占位 |
| `docs/openapi.yaml` | API 文档 |

---

## 技术支持

- 问题反馈：请提交 Issue 至项目仓库
- 文档查阅：参考 `docs/openapi.yaml` 了解 API 详情
- 开发调试：使用 `make dev` 启动热重载开发模式
