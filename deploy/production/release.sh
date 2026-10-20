#!/usr/bin/env bash
set -euo pipefail
umask 077
component=${1:?backend, admin or webapp}
release=${2:?release ID}
case "$component" in
  backend) service=api; key=BACKEND_IMAGE ;;
  admin) service=admin; key=ADMIN_IMAGE ;;
  webapp) service=webapp; key=WEBAPP_IMAGE ;;
  *) exit 2 ;;
esac
[[ $release =~ ^[0-9]+-[0-9]+$ ]]
cd /opt/vita
exec 9>release.lock
flock -w 900 9
test -f production.env
test -f images.env
image="vita/$component:$release"
archive="incoming/$component-$release/image.tar.gz"
test -f "$archive"
gzip -dc "$archive" | docker load
docker image inspect "$image" >/dev/null
compose=(docker compose --project-name vita-prod --env-file production.env --env-file images.env -f deploy/production/compose.yml)
infra=(docker compose --env-file infra.env -f deploy/docker-compose.prod-infra.yml)
previous=$(sed -n "s/^$key=//p" images.env)
test -n "$previous"
candidate=$(mktemp /opt/vita/images.candidate.XXXXXX)
trap 'rm -f "$candidate"' EXIT
awk -v key="$key" -v image="$image" 'index($0,key "=")==1 {$0=key "=" image} {print}' images.env > "$candidate"
candidate_compose=(docker compose --project-name vita-prod --env-file production.env --env-file "$candidate" -f deploy/production/compose.yml)
"${candidate_compose[@]}" config --quiet
if [[ $component == backend ]]; then
  install -d -m 700 backups
  backup="backups/pre-$release.dump"
  "${infra[@]}" exec -T postgres pg_dump -U vita -d vita -Fc > "$backup.partial"
  mv "$backup.partial" "$backup"
  # Migrations must remain additive so the previous backend can still run.
  "${candidate_compose[@]}" run --rm --no-deps migrate
fi
if ! "${candidate_compose[@]}" up -d --no-deps --wait --wait-timeout 180 "$service"; then
  printf 'Deployment failed. Previous image: %s\n' "$previous" >&2
  if [[ $previous != *:unreleased ]]; then
    "${compose[@]}" up -d --no-deps --wait --wait-timeout 180 "$service" || {
      printf 'Rollback failed; manual recovery required.\n' >&2
      exit 1
    }
  fi
  exit 1
fi
mv "$candidate" images.env
printf '%s %s %s previous=%s\n' "$(date -u +%FT%TZ)" "$component" "$image" "$previous" >> releases.log
if [[ $component == backend ]]; then
  # Admin's existing nginx config resolves api at startup. Reload it after
  # backend recreation so it does not retain the old container IP address.
  admin_id=$("${compose[@]}" ps -q admin)
  if [[ -n $admin_id ]]; then
    "${compose[@]}" exec -T admin nginx -s reload
  fi
fi
rm -f "$archive"
