.PHONY: help init init-backend init-admin init-webapp init-app init-website init-deploy install-deps install-backend install-admin install-webapp install-app install-website dev dev-mock be-run be-mock be-build be-test be-gen be-openapi be-fmt be-migrate be-rehash-migrations infra-up infra-down db-psql redis-cli app-gen app-run up down logs deploy deploy-docker deploy-docker-individual deploy-beta deploy-prod deploy-docker-infra deploy-up deploy-down deploy-logs deploy-build deploy-check deploy-clean clean clean-all backend-docker admin-docker webapp-docker app-docker website-docker docker-api docker-admin docker-webapp docker-website backend-install admin-install webapp-install app-install website-install backend-dev admin-dev webapp-dev app-dev website-dev backend-init admin-init webapp-init app-init website-init backend-build admin-build webapp-build app-build website-build backend-check admin-check webapp-check app-check website-check

help:
	@echo "=== Vita AI Companion ==="
	@echo ""
	@echo "用法: make [项目]-[命令]"
	@echo ""
	@echo "backend:"
	@echo "  make backend-init        初始化项目"
	@echo "  make backend-install     加载依赖"
	@echo "  make backend-dev         启动 API（宿主机模式，对接 Docker 中的 Postgres+Redis）"
	@echo "  make backend-build       构建"
	@echo "  make backend-check       检查"
	@echo "  make backend-docker      Docker 部署"
	@echo ""
	@echo "admin:"
	@echo "  make admin-init          初始化项目"
	@echo "  make admin-install       加载依赖"
	@echo "  make admin-dev           启动仪表盘"
	@echo "  make admin-build         构建"
	@echo "  make admin-check         检查"
	@echo "  make admin-docker        Docker 部署"
	@echo ""
	@echo "webapp:"
	@echo "  make webapp-init         初始化项目"
	@echo "  make webapp-install      加载依赖"
	@echo "  make webapp-dev          启动"
	@echo "  make webapp-build        构建"
	@echo "  make webapp-check        检查"
	@echo "  make webapp-docker       Docker 部署"
	@echo ""
	@echo "app:"
	@echo "  make app-init            初始化项目"
	@echo "  make app-install         加载依赖"
	@echo "  make app-dev             运行应用"
	@echo "  make app-build           构建"
	@echo "  make app-check           检查"
	@echo "  make app-docker          Docker 部署"
	@echo ""
	@echo "website:"
	@echo "  make website-init        初始化项目"
	@echo "  make website-install     加载依赖"
	@echo "  make website-dev         启动"
	@echo "  make website-build       构建"
	@echo "  make website-check       检查"
	@echo "  make website-docker      Docker 部署"
	@echo ""
	@echo "deploy:"
	@echo "  make infra-up            启动 Postgres + Redis（仅用于宿主机开发）"
	@echo "  make infra-down          停止 Postgres + Redis"
	@echo "  make db-psql             打开 psql 连接数据库"
	@echo "  make redis-cli           打开 redis-cli"
	@echo "  make dev                 infra-up + be-run（正常本地开发循环）"
	@echo "  make dev-mock            infra-up + be-mock（离线模拟模式）"
	@echo "  make be-run              宿主机运行 API（对接 Docker 中的 Postgres+Redis）"
	@echo "  make be-mock             be-run 的离线模拟版本"
	@echo "  make be-build            构建后端"
	@echo "  make be-test             运行后端测试"
	@echo "  make be-gen              重新生成 Ent 代码"
	@echo "  make be-fmt              格式化 Go 代码"
	@echo "  make be-migrate          生成数据库迁移"
	@echo "  make deploy-init         初始化部署配置"
	@echo "  make deploy-up           启动所有服务（Docker）"
	@echo "  make deploy-down         停止所有服务"
	@echo "  make deploy-logs         查看日志"
	@echo "  make deploy-build        构建所有镜像"
	@echo "  make deploy-check        检查所有服务"
	@echo "  make deploy-docker       Docker 一键部署"
	@echo "  make deploy-docker-individual 逐个 Docker 部署"
	@echo "  make deploy-beta         部署 beta"
	@echo "  make deploy-prod         部署生产"
	@echo ""
	@echo "全局:"
	@echo "  make init              初始化所有项目"
	@echo "  make install-deps      加载所有依赖"
	@echo "  make build             构建所有项目"
	@echo "  make check             检查所有项目"
	@echo "  make up                启动全部服务（Docker Compose）"
	@echo "  make down              停止全部服务"
	@echo "  make logs              查看日志"
	@echo "  make clean             清理构建产物"
	@echo "  make clean-all         清理所有依赖"

init: init-backend init-admin init-webapp init-app init-website init-deploy
	@echo "✅ All projects initialized!"

init-backend:
	@echo "📦 Initializing backend..." && mkdir -p backend/cmd/server backend/ent backend/internal/{config,db,handler,middleware,storage} backend/migrations backend/openapi && echo "✅ Backend initialized"

init-admin:
	@echo "📦 Initializing admin..." && mkdir -p admin/src && echo "✅ Admin initialized"

init-webapp:
	@echo "📦 Initializing webapp..." && mkdir -p webapp/src/app && echo "✅ Webapp initialized"

init-app:
	@echo "📦 Initializing app..." && mkdir -p app/lib/{core,features,shared} app/scripts && echo "✅ App initialized"

init-website:
	@echo "📦 Initializing website..." && mkdir -p website/src && echo "✅ Website initialized"

init-deploy:
	@echo "📦 Initializing deploy..." && mkdir -p deploy && cp deploy/.env.example deploy/.env 2>/dev/null; echo "✅ Deploy initialized"

install-deps: install-backend install-admin install-webapp install-app install-website
	@echo "✅ All dependencies installed!"

install-backend:
	@echo "📥 Installing backend dependencies..." && echo "✅ Backend ready"

install-admin:
	@echo "📥 Installing admin dependencies (pnpm)..." && echo "✅ Admin dependencies ready"

install-webapp:
	@echo "📥 Installing webapp dependencies (pnpm)..." && echo "✅ Webapp dependencies ready"

install-app:
	@echo "📥 Installing app dependencies..." && echo "✅ App dependencies ready"

install-website:
	@echo "📥 Installing website dependencies (pnpm)..." && echo "✅ Website dependencies ready"

backend-init: init-backend
backend-install: install-backend

# --- Infra (Postgres + Redis via Docker) ---
COMPOSE_DEV = docker compose -p vita

infra-up:
	@cd deploy && [ -f .env ] || cp .env.example .env && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml up -d && echo "✅ Postgres + Redis started"

infra-down:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml down && echo "✅ Postgres + Redis stopped"

db-psql:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml exec postgres psql -U $${POSTGRES_USER:-tovideo} -d $${POSTGRES_DB:-vita}

redis-cli:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml exec redis redis-cli

dev: infra-up be-run   ## start infra then run the API on the host (normal local loop)

# --- Backend dev (host mode, Docker infra) ---
DEV_ENV = set -a; [ -f deploy/.env ] && . deploy/.env; set +a; \
	export TOVIDEO_DB_DSN="host=localhost port=5433 user=tovideo password=$${POSTGRES_PASSWORD:-tovideo_dev_password} dbname=vita sslmode=disable"; \
	export TOVIDEO_REDIS_URL="redis://localhost:$${REDIS_PORT:-6380}/0"; \
	export TOVIDEO_JWT_SECRET="$${TOVIDEO_JWT_SECRET:-dev-secret-change-me-32-characters-min}"; \
	export TOVIDEO_HTTP_ADDR=":$${SERVER_PORT:-8080}"; \
	export TOVIDEO_AUTO_MIGRATE="true"; \
	export TOVIDEO_MOCK_GENERATION="false"; \
	export TOVIDEO_TEMPLATE_STAGES="$${TOVIDEO_TEMPLATE_STAGES:-released,beta,preview}"; \
	export TOVIDEO_MODEL_STAGES="$${TOVIDEO_MODEL_STAGES:-released,beta,preview}";
	export TOVIDEO_MOCK_GENERATION="false"; \
	export TOVIDEO_TEMPLATE_STAGES="$${TOVIDEO_TEMPLATE_STAGES:-released,beta,preview}"; \
	export TOVIDEO_MODEL_STAGES="$${TOVIDEO_MODEL_STAGES:-released,beta,preview}";

dev: infra-up be-run   ## start infra then run the API on the host (normal local loop)

dev-mock: infra-up be-mock   ## host-mode: infra-up + be-mock (mock generation)

be-run:            ## run API on host against dockerized Postgres + Redis
	@$(DEV_ENV) export TOVIDEO_MOCK_GENERATION=false; cd backend && go run ./cmd/server

be-mock:           ## be-run with offline mock generation
	@$(DEV_ENV) export TOVIDEO_MOCK_GENERATION=true; cd backend && go run ./cmd/server

be-build:
	@cd backend && go build ./...

be-test:           ## unit/integration tests
	@cd backend && go test ./...

be-gen:            ## regenerate Ent code after editing ent/schema
	@cd backend && go generate ./ent

be-openapi:        ## regenerate openapi.json
	@cd backend && go run ./cmd/genopenapi 2>/dev/null || echo "OpenAPI generation skipped"

be-fmt:
	@cd backend && gofmt -w cmd internal ent/schema

be-migrate:        ## generate a versioned migration
	@cd backend && go run ./cmd/migrate $(NAME) 2>/dev/null || echo "Migration generation skipped"

be-rehash-migrations: ## recompute migration checksums
	@cd backend && go run ./cmd/rehashmigrations 2>/dev/null || echo "Rehash skipped"

backend-dev: be-run
backend-build: be-build
backend-check: be-test

# --- Docker full stack ---
up:
	@cd deploy && [ -f .env ] || cp .env.example .env && $(COMPOSE_DEV) -f docker-compose.dev.yml up --build -d && echo "✅ Full stack deployed with Docker Compose"

down:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml down && echo "✅ All services stopped"

logs:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml logs -f api

deploy-docker: deploy-docker-dev
	@echo "✅ Docker one-click deployment complete!"

deploy-docker-dev:
	@cd deploy && [ -f .env ] || cp .env.example .env && $(COMPOSE_DEV) -f docker-compose.dev.yml up --build -d && echo "✅ Full stack deployed with Docker Compose"

deploy-docker-individual: docker-api docker-admin docker-webapp docker-website deploy-docker-infra
	@echo "✅ Individual Docker deployment complete!"

docker-api:
	@cd deploy && docker build -f ../backend/Dockerfile -t vita/backend:dev ../backend && docker run -d --name vita-backend -p 8260:8080 --network vita-net --depends-on vita-postgres --depends-on vita-redis vita/backend:dev && echo "✅ API container deployed"

docker-admin:
	@cd deploy && docker build -f ../admin/Dockerfile -t vita/admin:dev ../admin && docker run -d --name vita-admin -p 8261:80 --network vita-net --depends-on vita-api vita/admin:dev && echo "✅ Admin container deployed"

docker-webapp:
	@cd deploy && docker build -f ../webapp/Dockerfile -t vita/webapp:dev .. && docker run -d --name vita-webapp -p 8263:3000 --network vita-net --depends-on vita-api vita/webapp:dev && echo "✅ Webapp container deployed"

docker-website:
	@cd deploy && docker build -f ../website/Dockerfile -t vita/website:dev . && docker run -d --name vita-website -p 8262:80 --network vita-net vita/website:dev && echo "✅ Website container deployed"

docker-app:
	@echo "⚠️  Flutter app uses make app-dev instead of Docker"

deploy-docker-infra: infra-up

deploy-up: deploy-docker
deploy-down: down
deploy-logs: logs
deploy-build:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml build && echo "✅ All services built"
deploy-check:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml ps && echo "✅ All services checked"
deploy-clean:
	@cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml down -v && echo "✅ Deploy cleaned"

deploy-beta:
	@cd deploy && [ -f .env.beta ] || cp .env.beta.example .env.beta && docker compose -p vita-beta -f docker-compose.beta.yml --env-file .env.beta up -d --build && echo "✅ Beta deployment complete!"

deploy-prod:
	@cd deploy && [ -f .env.prod ] || cp .env.prod.example .env.prod && docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod up -d --build && echo "✅ Production deployment complete!"

dev: infra-up be-run

# --- Admin ---
admin-init: init-admin
admin-install: install-admin
admin-dev:
	@cd admin && pnpm dev
admin-build:
	@cd admin && pnpm build
admin-check:
	@cd admin && pnpm typecheck
admin-docker:
	@cd deploy && docker build -f ../admin/Dockerfile -t vita/admin:dev ../admin && docker run -d --name vita-admin -p 8261:80 --network vita-net --depends-on vita-api vita/admin:dev && echo "✅ Admin container deployed"

# --- Webapp ---
webapp-init: init-webapp
webapp-install: install-webapp
webapp-dev:
	@cd webapp && pnpm dev
webapp-build:
	@cd webapp && pnpm build
webapp-check:
	@cd webapp && pnpm typecheck
webapp-docker:
	@cd deploy && docker build -f ../webapp/Dockerfile -t vita/webapp:dev .. && docker run -d --name vita-webapp -p 8263:3000 --network vita-net --depends-on vita-api vita/webapp:dev && echo "✅ Webapp container deployed"

# --- App ---
app-init: init-app
app-install: install-app
app-dev:
	@cd app && flutter run 2>/dev/null || echo "⚠️  Flutter not available"
app-build:
	@cd app && flutter build apk 2>/dev/null || echo "⚠️  Flutter not available"
app-check:
	@cd app && flutter analyze 2>/dev/null || echo "⚠️  Flutter not available"
app-docker:
	@echo "⚠️  Flutter app uses make app-dev instead of Docker"

# --- Website ---
website-init: init-website
website-install: install-website
website-dev:
	@cd website && pnpm dev
website-build:
	@cd website && pnpm build
website-check:
	@cd website && pnpm typecheck
website-docker:
	@cd deploy && docker build -f ../website/Dockerfile -t vita/website:dev . && docker run -d --name vita-website -p 8262:80 --network vita-net vita/website:dev && echo "✅ Website container deployed"

# --- Global ---
build: backend-build admin-build webapp-build app-build website-build
	@echo "✅ All projects built"

check: backend-check admin-check webapp-check app-check website-check
	@echo "✅ All projects checked"

clean:
	@cd backend && rm -rf openapi/ent generated && cd admin && rm -rf dist node_modules && cd webapp && rm -rf .next node_modules && cd website && rm -rf dist node_modules && cd app && rm -rf .dart_tool build && echo "✅ Build artifacts cleaned"

clean-all: clean
	@cd admin && rm -rf node_modules 2>/dev/null; cd webapp && rm -rf node_modules 2>/dev/null; cd website && rm -rf node_modules 2>/dev/null; echo "✅ All dependencies cleaned"

app-gen:
	@cd app && ./scripts/gen_api.sh 2>/dev/null || echo "API generation skipped"
