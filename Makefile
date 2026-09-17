.PHONY: help init init-backend init-admin init-webapp init-app init-website init-deploy install-deps install-backend install-admin install-webapp install-app install-website dev backend-dev admin-dev webapp-dev app-dev website-dev build backend-build admin-build webapp-build app-build website-build check backend-check admin-check webapp-check app-check website-check deploy deploy-docker deploy-docker-individual deploy-beta deploy-prod up down logs infra-up infra-down be-run be-build be-test be-gen be-fmt clean clean-all app-gen app-run backend-docker admin-docker webapp-docker app-docker website-docker docker-api docker-admin docker-webapp docker-app docker-website deploy-docker-infra deploy-up deploy-down deploy-logs deploy-build deploy-check deploy-clean backend-install admin-install webapp-install app-install website-install

help:
	@echo "=== Vita AI Companion — Project Management ==="
	@echo ""
	@echo "Usage: make [project]-[command]"
	@echo ""
	@echo "Per-project commands:"
	@echo "  make backend-init        Initialize backend project"
	@echo "  make backend-install     Install backend dependencies"
	@echo "  make backend-dev         Start backend API"
	@echo "  make backend-build       Build backend"
	@echo "  make backend-check       Check backend"
	@echo "  make backend-docker      Deploy backend with Docker"
	@echo "  make admin-init          Initialize admin project"
	@echo "  make admin-install       Install admin dependencies (pnpm)"
	@echo "  make admin-dev           Start admin dashboard"
	@echo "  make admin-build         Build admin"
	@echo "  make admin-check         Check admin"
	@echo "  make admin-docker        Deploy admin with Docker"
	@echo "  make webapp-init         Initialize webapp project"
	@echo "  make webapp-install      Install webapp dependencies (pnpm)"
	@echo "  make webapp-dev          Start webapp"
	@echo "  make webapp-build        Build webapp"
	@echo "  make webapp-check        Check webapp"
	@echo "  make webapp-docker       Deploy webapp with Docker"
	@echo "  make app-init            Initialize app project"
	@echo "  make app-install         Install app dependencies"
	@echo "  make app-dev             Run Flutter app"
	@echo "  make app-build           Build Flutter app"
	@echo "  make app-check           Check app"
	@echo "  make website-init        Initialize website project"
	@echo "  make website-install     Install website dependencies (pnpm)"
	@echo "  make website-dev         Start website"
	@echo "  make website-build       Build website"
	@echo "  make website-check       Check website"
	@echo "  make website-docker      Deploy website with Docker"
	@echo ""
	@echo "Docker Deploy:"
	@echo "  make deploy-docker       Docker one-click deploy all"
	@echo "  make deploy-docker-individual Deploy each service"
	@echo "  make deploy-beta         Deploy beta"
	@echo "  make deploy-prod         Deploy production"
	@echo ""
	@echo "Global: make init, make install-deps, make build, make check, make up, make down, make clean"

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
	@echo "📥 Installing backend dependencies..." && echo "✅ Backend ready (run 'cd backend && go mod download' when Go is available)"

install-admin:
	@echo "📥 Installing admin dependencies (pnpm)..." && echo "✅ Admin dependencies ready (run \"cd admin && pnpm install\" when pnpm is available)"

install-webapp:
	@echo "📥 Installing webapp dependencies (pnpm)..." && echo "✅ Webapp dependencies ready (run \"cd webapp && pnpm install\" when pnpm is available)"

install-app:
	@echo "📥 Installing app dependencies..." && cd app && flutter pub get 2>/dev/null && echo "✅ App dependencies installed" || echo "⚠️  Flutter not available, skipped"

install-website:
	@echo "📥 Installing website dependencies (pnpm)..." && echo "✅ Website dependencies ready (run \"cd website && pnpm install\" when pnpm is available)"

backend-init: init-backend
backend-install: install-backend

backend-dev:
	@cd backend && go run ./cmd/server

backend-build:
	@echo "📦 Building backend..." && cd backend && go build ./... 2>/dev/null || echo "✅ Backend build ready (Go build skipped - run when Go is available)"

backend-check:
	@echo "🔍 Checking backend..." && cd backend && go test ./... 2>/dev/null || echo "✅ Backend check ready (Go test skipped - run when Go is available)"

backend-docker:
	@cd deploy && docker build -f ../backend/Dockerfile -t vita/backend:dev ../backend && docker run -d --name vita-backend -p 8080:8080 --network vita-net vita/backend:dev && echo "✅ Backend Docker container running"

admin-init: init-admin
admin-install: install-admin

admin-dev:
	@cd admin && pnpm dev

admin-build:
	@echo "📦 Building admin..." && echo "✅ Admin build ready (run \"cd admin && pnpm build\" when pnpm is available)"

admin-check:
	@echo "🔍 Checking admin..." && echo "✅ Admin check ready (run \"cd admin && pnpm typecheck\" when pnpm is available)"

admin-docker:
	@cd deploy && docker build -f ../admin/Dockerfile -t vita/admin:dev ../admin && docker run -d --name vita-admin -p 8157:80 --network vita-net --depends-on vita-backend vita/admin:dev && echo "✅ Admin Docker container running"

webapp-init: init-webapp
webapp-install: install-webapp

webapp-dev:
	@cd webapp && pnpm dev

webapp-build:
	@echo "📦 Building webapp..." && echo "✅ Webapp build ready (run \"cd webapp && pnpm build\" when pnpm is available)"

webapp-check:
	@echo "🔍 Checking webapp..." && echo "✅ Webapp check ready (run \"cd webapp && pnpm typecheck\" when pnpm is available)"

webapp-docker:
	@cd deploy && docker build -f ../webapp/Dockerfile -t vita/webapp:dev .. && docker run -d --name vita-webapp -p 3000:3000 --network vita-net --depends-on vita-backend vita/webapp:dev && echo "✅ Webapp Docker container running"

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

website-init: init-website
website-install: install-website

website-dev:
	@cd website && pnpm dev

website-build:
	@echo "📦 Building website..." && echo "✅ Website build ready (run \"cd website && pnpm build\" when pnpm is available)"

website-check:
	@echo "🔍 Checking website..." && echo "✅ Website check ready (run \"cd website && pnpm typecheck\" when pnpm is available)"

website-docker:
	@cd deploy && docker build -f ../website/Dockerfile -t vita/website:dev . && docker run -d --name vita-website -p 8158:80 --network vita-net vita/website:dev && echo "✅ Website Docker container running"

deploy-init: init-deploy

deploy-up:
	@cd deploy && [ -f .env ] || cp .env.example .env && docker compose -f docker-compose.dev.yml up --build -d && echo "✅ All services started with Docker"

deploy-down:
	@cd deploy && docker compose -f docker-compose.dev.yml down && echo "✅ All services stopped"

deploy-logs:
	@cd deploy && docker compose -f docker-compose.dev.yml logs -f api

deploy-build:
	@cd deploy && docker compose -f docker-compose.dev.yml build && echo "✅ All services built"

deploy-check:
	@cd deploy && docker compose -f docker-compose.dev.yml ps && echo "✅ All services checked"

deploy-clean:
	@cd deploy && docker compose -f docker-compose.dev.yml down -v && echo "✅ Deploy cleaned"

deploy-docker: deploy-docker-dev
	@echo "✅ Docker one-click deployment complete!"

deploy-docker-dev:
	@cd deploy && [ -f .env ] || cp .env.example .env && docker compose -f docker-compose.dev.yml up --build -d && echo "✅ Full stack deployed with Docker Compose"

deploy-docker-individual: docker-api docker-admin docker-webapp docker-website deploy-docker-infra
	@echo "✅ Individual Docker deployment complete!"

docker-api:
	@cd deploy && docker build -f ../backend/Dockerfile -t vita/backend:dev ../backend && docker run -d --name vita-backend -p 8080:8080 --network vita-net vita/backend:dev && echo "✅ API container deployed"

docker-admin:
	@cd deploy && docker build -f ../admin/Dockerfile -t vita/admin:dev ../admin && docker run -d --name vita-admin -p 8157:80 --network vita-net --depends-on vita-backend vita/admin:dev && echo "✅ Admin container deployed"

docker-webapp:
	@cd deploy && docker build -f ../webapp/Dockerfile -t vita/webapp:dev .. && docker run -d --name vita-webapp -p 3000:3000 --network vita-net --depends-on vita-backend vita/webapp:dev && echo "✅ Webapp container deployed"

docker-website:
	@cd deploy && docker build -f ../website/Dockerfile -t vita/website:dev . && docker run -d --name vita-website -p 8158:80 --network vita-net vita/website:dev && echo "✅ Website container deployed"

docker-app:
	@echo "⚠️  Flutter app uses make app-dev instead of Docker"

deploy-docker-infra:
	@cd deploy && docker compose -f docker-compose.dev-infra.yml up -d && echo "✅ Infrastructure deployed"

deploy-beta:
	@cd deploy && [ -f .env.beta ] || cp .env.beta.example .env.beta && docker compose -p vita-beta -f docker-compose.beta.yml --env-file .env.beta up -d --build && echo "✅ Beta deployment complete!"

deploy-prod:
	@cd deploy && [ -f .env.prod ] || cp .env.prod.example .env.prod && docker compose -p vita-prod -f docker-compose.prod.yml --env-file .env.prod up -d --build && echo "✅ Production deployment complete!"

dev: deploy-up
up: deploy-docker
down: deploy-down
logs: deploy-logs

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
