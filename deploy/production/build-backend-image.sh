#!/usr/bin/env bash
# Local build only: no upload, migration or deployment is performed.
set -euo pipefail
umask 077
root=$(cd "$(dirname "$0")/../.." && pwd)
tag=${IMAGE_TAG:-local-$(date -u +%Y%m%d%H%M%S)}
platform=${IMAGE_PLATFORM:-linux/amd64}
[[ $tag =~ ^local-[A-Za-z0-9][A-Za-z0-9_.-]{0,121}$ ]] || { echo 'Invalid IMAGE_TAG' >&2; exit 2; }
# The production host is amd64. Reject incompatible archives before uploading.
[[ $platform == linux/amd64 ]] || { echo 'IMAGE_PLATFORM must be linux/amd64 for this deployment' >&2; exit 2; }
image="vita/backend:$tag"
output=${IMAGE_OUTPUT_DIR:-$root/dist/images}
command -v docker >/dev/null
docker buildx version >/dev/null
docker info >/dev/null
mkdir -p "$output"
[[ ! -e $output/backend.tar.gz.partial ]] || {
  echo "Incomplete archive exists in $output; check whether another build is running" >&2; exit 2;
}
docker buildx build --platform "$platform" --load -t "$image" -f "$root/backend/Dockerfile" "$root/backend"
[[ $(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image") == "$platform" ]]
trap 'rm -f "$output/backend.tar.gz.partial"' EXIT
# The archive contains this dedicated transport tag. Deployment retags it with
# the Jenkins build number; existing rollback tags are never overwritten.
docker tag "$image" vita/backend:uploaded
docker save vita/backend:uploaded | gzip -1 > "$output/backend.tar.gz.partial"
mv "$output/backend.tar.gz.partial" "$output/backend.tar.gz"
printf '\nImage: %s\nArchive: %s/backend.tar.gz\n' "$image" "$output"
printf 'Upload backend.tar.gz to /opt/vita/incoming/backend.tar.gz, then run Jenkins with BUILD_SOURCE=uploaded.\n'
