.PHONY: help \
	init init-backend init-admin init-webapp init-app init-website init-deploy \
	install-deps admin-install webapp-install website-install \
	infra-up infra-down db-psql redis-cli \
	dev dev-mock be-run be-mock be-build be-test be-gen be-openapi be-fmt be-migrate be-rehash-migrations \
	up down logs \
	deploy-docker deploy-docker-individual docker-api docker-admin docker-webapp docker-website \
	deploy-up deploy-down deploy-logs deploy-build deploy-check deploy-clean deploy-beta deploy-prod \
	admin-dev admin-build admin-check \
	webapp-dev webapp-build webapp-check \
	app-prepare-dirs app-run app-run-beta app-run-prod app-dev app-build-apk-beta app-build-apk app-build-ios-beta app-build-ios app-check app-gen \
	website-dev website-build website-check \
	build check clean clean-all

help:
	@echo "=== Vita AI Companion ==="
	@echo ""
	@echo "用法: make [项目]-[命令]"
	@echo ""
	@echo "backend (Go):"
	@echo "  make be-run              宿主机运行 API（对接 Docker 中的 Postgres+Redis）"
	@echo "  make be-mock             be-run 的离线模拟版本"
	@echo "  make be-build            构建后端"
	@echo "  make be-test             运行后端测试"
	@echo "  make be-gen              重新生成 Ent 代码"
	@echo "  make be-openapi          重新生成 openapi.json"
	@echo "  make be-fmt              格式化 Go 代码"
	@echo "  make be-migrate          生成数据库迁移"
	@echo "  make be-rehash-migrations 重算迁移校验和"
	@echo ""
	@echo "admin (pnpm):"
	@echo "  make admin-install       安装依赖"
	@echo "  make admin-dev           启动仪表盘"
	@echo "  make admin-build         构建"
	@echo "  make admin-check         类型检查"
	@echo ""
	@echo "webapp (pnpm):"
	@echo "  make webapp-install      安装依赖"
	@echo "  make webapp-dev          启动"
	@echo "  make webapp-build        构建"
	@echo "  make webapp-check        类型检查"
	@echo ""
	@echo "app (Flutter):"
	@echo "  make app-run             运行 dev 环境"
	@echo "  make app-run-beta        运行 beta 环境"
	@echo "  make app-run-prod        运行 prod 环境"
	@echo "  make app-dev             运行应用（= app-run）"
	@echo "  make app-build-apk-beta  构建 beta APK"
	@echo "  make app-build-apk       构建 prod APK"
	@echo "  make app-build-ios-beta  构建 beta iOS（no-codesign）"
	@echo "  make app-build-ios       构建 prod iOS（no-codesign）"
	@echo "  make app-check           flutter analyze"
	@echo "  make app-gen             重新生成 API 客户端代码"
	@echo ""
	@echo "website (pnpm):"
	@echo "  make website-install     安装依赖"
	@echo "  make website-dev         启动"
	@echo "  make website-build       构建"
	@echo "  make website-check       类型检查"
	@echo ""
	@echo "deploy:"
	@echo "  make infra-up            启动 Postgres + Redis（仅用于宿主机开发）"
	@echo "  make infra-down          停止 Postgres + Redis"
	@echo "  make db-psql             打开 psql 连接数据库"
	@echo "  make redis-cli           打开 redis-cli"
	@echo "  make dev                 infra-up + be-run（正常本地开发循环）"
	@echo "  make dev-mock            infra-up + be-mock（离线模拟模式）"
	@echo "  make up                  启动全部服务（Docker Compose）"
	@echo "  make down                停止全部服务"
	@echo "  make logs                查看 api 日志"
	@echo "  make deploy-docker       Docker 一键部署（= up）"
	@echo "  make deploy-docker-individual  逐个 Docker 部署"
	@echo "  make deploy-build        构建所有镜像"
	@echo "  make deploy-check        检查所有服务"
	@echo "  make deploy-clean        清理部署（含数据卷）"
	@echo "  make deploy-beta         部署 beta"
	@echo "  make deploy-prod         部署生产"
	@echo ""
	@echo "全局:"
	@echo "  make init                初始化所有项目目录"
	@echo "  make install-deps        安装所有前端依赖"
	@echo "  make build               构建所有项目"
	@echo "  make check               检查所有项目"
	@echo "  make clean               清理构建产物"
	@echo "  make clean-all           清理所有依赖与构建产物"

init: init-backend init-admin init-webapp init-app init-website init-deploy
	@echo "✅ All projects initialized!"

init-backend:
	mkdir -p backend/cmd/server backend/ent backend/internal/config backend/internal/db backend/internal/handler backend/internal/middleware backend/internal/storage backend/migrations backend/openapi
	@echo "✅ Backend dirs created"

init-admin:
	mkdir -p admin/src
	@echo "✅ Admin dirs created"

init-webapp:
	mkdir -p webapp/src/app
	@echo "✅ Webapp dirs created"

init-app:
	mkdir -p app/lib/core app/lib/features app/lib/shared app/scripts
	@echo "✅ App dirs created"

init-website:
	mkdir -p website/src
	@echo "✅ Website dirs created"

init-deploy:
	mkdir -p deploy
	cp -n deploy/.env.example deploy/.env 2>/dev/null || true
	@echo "✅ Deploy dirs created"

install-deps: admin-install webapp-install website-install
	@echo "✅ All dependencies installed!"

admin-install:
	cd admin && pnpm install
	@echo "✅ Admin dependencies ready"

webapp-install:
	cd webapp && pnpm install
	@echo "✅ Webapp dependencies ready"

website-install:
	cd website && pnpm install
	@echo "✅ Website dependencies ready"

# --- Infra (Postgres + Redis via Docker) ---
COMPOSE_DEV = docker compose -p vita

infra-up:
	cd deploy && [ -f .env ] || cp .env.example .env
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml up -d
	@echo "✅ Postgres + Redis started"

infra-down:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml down
	@echo "✅ Postgres + Redis stopped"

db-psql:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml exec postgres psql -U $${POSTGRES_USER:-tovideo} -d $${POSTGRES_DB:-vita}

redis-cli:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev-infra.yml exec redis redis-cli

# --- Backend dev (host mode, Docker infra) ---
DEV_ENV = set -a; [ -f deploy/.env ] && . deploy/.env; set +a; \
	export VITA_DB_DSN="host=localhost port=5433 user=tovideo password=$${POSTGRES_PASSWORD:-tovideo_dev_password} dbname=vita sslmode=disable"; \
	export VITA_REDIS_URL="redis://localhost:$${REDIS_PORT:-6380}/0"; \
	export VITA_JWT_SECRET="$${VITA_JWT_SECRET:-dev-secret-change-me-32-characters-min}"; \
	export VITA_HTTP_ADDR=":$${SERVER_PORT:-8080}"; \
	export VITA_AUTO_MIGRATE="true"; \
	export VITA_MOCK_GENERATION="false"; \
	export VITA_TEMPLATE_STAGES="$${VITA_TEMPLATE_STAGES:-released,beta,preview}"; \
	export VITA_MODEL_STAGES="$${VITA_MODEL_STAGES:-released,beta,preview}";

dev: infra-up be-run

dev-mock: infra-up be-mock

be-run:
	$(DEV_ENV) export VITA_MOCK_GENERATION=false; cd backend && go run ./cmd/server

be-mock:
	$(DEV_ENV) export VITA_MOCK_GENERATION=true; cd backend && go run ./cmd/server

be-build:
	cd backend && go build ./...

be-test:
	cd backend && go test ./...

be-gen:
	@if [ -d backend/ent ]; then \
		cd backend && go generate ./ent; \
	else \
		echo "⚠️  backend/ent not found, skip Ent generation"; \
	fi

be-openapi:
	@cd backend && go run ./cmd/genopenapi 2>/dev/null || echo "OpenAPI generation skipped"

be-fmt:
	cd backend && if [ -d ent/schema ]; then gofmt -w cmd internal ent/schema; else gofmt -w cmd internal; fi

be-migrate:
	cd backend && go run ./cmd/migrate

be-rehash-migrations:
	@cd backend && go run ./cmd/rehashmigrations 2>/dev/null || echo "Rehash skipped"

# --- Docker full stack ---
up:
	cd deploy && [ -f .env ] || cp .env.example .env
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml up --build -d
	@echo "✅ Full stack deployed with Docker Compose"

down:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml down
	@echo "✅ All services stopped"

logs:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml logs -f api

deploy-docker: up

deploy-docker-individual: docker-api docker-admin docker-webapp docker-website infra-up
	@echo "✅ Individual Docker deployment complete!"

docker-api:
	cd deploy && docker build -f ../backend/Dockerfile -t vita/backend:dev ../backend && docker run -d --name vita-backend -p 8260:8080 --network vita-net --depends-on vita-postgres --depends-on vita-redis vita/backend:dev
	@echo "✅ API container deployed"

docker-admin:
	cd deploy && docker build -f ../admin/Dockerfile -t vita/admin:dev ../admin && docker run -d --name vita-admin -p 8261:80 --network vita-net --depends-on vita-api vita/admin:dev
	@echo "✅ Admin container deployed"

docker-webapp:
	cd deploy && docker build -f ../webapp/Dockerfile -t vita/webapp:dev .. && docker run -d --name vita-webapp -p 8263:3000 --network vita-net --depends-on vita-api vita/webapp:dev
	@echo "✅ Webapp container deployed"

docker-website:
	cd deploy && docker build -f ../website/Dockerfile -t vita/website:dev . && docker run -d --name vita-website -p 8262:80 --network vita-net vita/website:dev
	@echo "✅ Website container deployed"

deploy-up: up
deploy-down: down
deploy-logs: logs

deploy-build:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml build
	@echo "✅ All services built"

deploy-check:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml ps
	@echo "✅ All services checked"

deploy-clean:
	cd deploy && $(COMPOSE_DEV) -f docker-compose.dev.yml down -v
	@echo "✅ Deploy cleaned"

deploy-beta:
	cd deploy && [ -f .env.beta ] || cp .env.beta.example .env.beta
	cd deploy && docker compose -p vita-beta -f docker-compose.beta.yml --env-file .env.beta up -d --build
	@echo "✅ Beta deployment complete!"

deploy-prod:
	cd deploy && [ -f .env.prod ] || cp .env.prod.example .env.prod
	cd deploy && docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod up -d --build
	@echo "✅ Production deployment complete!"

# --- Admin ---
admin-dev:
	cd admin && pnpm dev

admin-build:
	cd admin && pnpm build

admin-check:
	cd admin && pnpm typecheck

# --- Webapp ---
webapp-dev:
	cd webapp && pnpm dev

webapp-build:
	cd webapp && pnpm build

webapp-check:
	cd webapp && pnpm typecheck

# --- App (Flutter) ---
# On Windows/MSYS, invoke flutter via cmd.exe /c flutter.bat: the unix `flutter`
# shell script exec's flutter.bat, which loses args and TTY when make runs it
# through `sh -c`.
ifeq ($(OS),Windows_NT)
FLUTTER_CMD = flutter.bat
else
FLUTTER_CMD = flutter
endif

# App API base URL, injected at build time via --dart-define (dev only).
# iOS and Android currently share the same dev endpoint; if the Android
# emulator cannot reach the host backend, change APP_API_URL_ANDROID to
# http://10.0.2.2:8260 (host loopback as seen from the emulator).
APP_API_URL_IOS     = http://127.0.0.1:8260
APP_API_URL_ANDROID = http://10.0.2.2:8260
APP_API_URL         = $(APP_API_URL_ANDROID)
# China mirrors for pub packages and Flutter engine artifacts so that
# `flutter pub get` / `flutter precache` are reachable from mainland China.
# Override by exporting PUB_HOSTED_URL / FLUTTER_STORAGE_BASE_URL before make.
PUB_HOSTED_URL ?= https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL ?= https://storage.flutter-io.cn
# GitHub clones (e.g. firebase-ios-sdk pulled by CocoaPods via a git source) go
# through the machine's local proxy, configured globally in ~/.gitconfig as
# http.https://github.com.proxy -- nothing project-specific needed here.
FLUTTER_ENV = PUB_HOSTED_URL=$(PUB_HOSTED_URL) FLUTTER_STORAGE_BASE_URL=$(FLUTTER_STORAGE_BASE_URL)

app-prepare-dirs:
	mkdir -p app/build/ios/SourcePackages app/build/macos/SourcePackages app/.cocoapods-local app/.home

app-run: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) PUB_CACHE="$${PUB_CACHE:-$$HOME/.pub-cache}" HOME="$$(pwd)/.home" CP_HOME_DIR="$$(pwd)/.cocoapods-local" $(FLUTTER_CMD) run --dart-define-from-file=config/dev.json --dart-define=VITA_API_BASE_URL=$(APP_API_URL)

app-run-beta: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) PUB_CACHE="$${PUB_CACHE:-$$HOME/.pub-cache}" HOME="$$(pwd)/.home" CP_HOME_DIR="$$(pwd)/.cocoapods-local" $(FLUTTER_CMD) run --dart-define-from-file=config/beta.json

app-run-prod: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) PUB_CACHE="$${PUB_CACHE:-$$HOME/.pub-cache}" HOME="$$(pwd)/.home" CP_HOME_DIR="$$(pwd)/.cocoapods-local" $(FLUTTER_CMD) run --dart-define-from-file=config/prod.json

app-dev: app-run

app-build-apk-beta: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) $(FLUTTER_CMD) build apk --release --dart-define-from-file=config/beta.json

app-build-apk: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) $(FLUTTER_CMD) build apk --release --dart-define-from-file=config/prod.json

app-build-ios-beta: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) PUB_CACHE="$${PUB_CACHE:-$$HOME/.pub-cache}" HOME="$$(pwd)/.home" CP_HOME_DIR="$$(pwd)/.cocoapods-local" $(FLUTTER_CMD) build ios --release --no-codesign --dart-define-from-file=config/beta.json

app-build-ios: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) PUB_CACHE="$${PUB_CACHE:-$$HOME/.pub-cache}" HOME="$$(pwd)/.home" CP_HOME_DIR="$$(pwd)/.cocoapods-local" $(FLUTTER_CMD) build ios --release --no-codesign --dart-define-from-file=config/prod.json

app-check: app-prepare-dirs
	@cd app && command -v flutter >/dev/null 2>&1 || { echo "⚠️  Flutter not available"; exit 1; }
	cd app && $(FLUTTER_ENV) $(FLUTTER_CMD) analyze

app-gen:
	@cd app && ./scripts/gen_api.sh 2>/dev/null || echo "API generation skipped"

# --- Website ---
website-dev:
	cd website && pnpm dev

website-build:
	cd website && pnpm build

website-check:
	cd website && pnpm typecheck

# --- Global ---
build: be-build admin-build webapp-build app-build-apk website-build
	@echo "✅ All projects built"

check: be-test admin-check webapp-check app-check website-check
	@echo "✅ All projects checked"

clean:
	cd backend && rm -rf openapi/ent generated
	cd admin && rm -rf dist node_modules
	cd webapp && rm -rf .next node_modules
	cd website && rm -rf dist node_modules
	cd app && rm -rf .dart_tool build
	@echo "✅ Build artifacts cleaned"

clean-all: clean
	@echo "✅ All dependencies cleaned"
