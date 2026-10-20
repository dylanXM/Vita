#!/usr/bin/env bash
set -euo pipefail
umask 077
# Install this repository's deploy/ directory at /opt/vita/deploy first.
# This starts only new Vita infrastructure; applications require a release.
cd /opt/vita
for tool in docker openssl flock; do command -v "$tool" >/dev/null; done
docker compose version >/dev/null
exec 9>release.lock
flock -w 30 9
if [[ -e infra.env || -e production.env || -e images.env ]]; then
  printf 'Existing Vita configuration found; refusing to overwrite credentials.\n' >&2
  exit 1
fi
postgres_password=$(openssl rand -hex 32)
redis_password=$(openssl rand -hex 32)
jwt_secret=$(openssl rand -hex 32)
agent_secret=$(openssl rand -hex 32)
cat > infra.env <<EOF
POSTGRES_PASSWORD=$postgres_password
REDIS_PASSWORD=$redis_password
EOF
cat > production.env <<EOF
VITA_ENV=prod
VITA_DB_DSN=postgres://vita:$postgres_password@vita-postgres:5432/vita?sslmode=disable
VITA_REDIS_URL=redis://:$redis_password@vita-redis:6379/0
VITA_JWT_SECRET=$jwt_secret
VITA_AGENT_CONFIG_KEY=$agent_secret
VITA_ALLOWED_ORIGINS=https://vita-admin.sweetai.work,https://vita-app.sweetai.work
VITA_AUTO_MIGRATE=false
VITA_MOCK_GENERATION=false
WEBAPP_API_URL=https://vita-api.sweetai.work
WEBAPP_ENV=prod
BIND_HOST=127.0.0.1
SERVER_PORT=8270
ADMIN_BIND_HOST=127.0.0.1
ADMIN_PORT=8261
WEBAPP_BIND_HOST=127.0.0.1
WEBAPP_PORT=8263
EOF
cat > images.env <<'EOF'
BACKEND_IMAGE=vita/backend:unreleased
ADMIN_IMAGE=vita/admin:unreleased
WEBAPP_IMAGE=vita/webapp:unreleased
EOF
install -d -m 700 incoming backups
docker compose --env-file infra.env -f deploy/docker-compose.prod-infra.yml config --quiet
docker compose --env-file infra.env -f deploy/docker-compose.prod-infra.yml up -d --wait --wait-timeout 180
printf 'Vita PostgreSQL and Redis are healthy. Configure production.env integrations before first backend release.\n'
