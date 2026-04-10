#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  release-ecs.sh --host HOST --user USER --password PASS [options]

Options:
  --host HOST                  ECS public IP or hostname
  --port PORT                  SSH port (default: 22)
  --user USER                  SSH login user
  --password PASS              SSH password
  --app-port PORT              DeerFlow exposed port on ECS (default: 2026)
  --tag TAG                    Image tag to build/push/deploy (default: myagent)
  --runtime-mode MODE          standard or gateway (default: standard)
  --push-registry-host HOST:PORT    Registry host used locally for docker login/push (default: 101.201.37.112:5000)
  --deploy-registry-host HOST:PORT  Registry host used on ECS for docker pull (default: 127.0.0.1:5000)
  --registry-user USER         Registry username (default: admin)
  --registry-password PASS     Registry password (default: value from docs/docker-registry-info.md)
EOF
}

HOST=
SSH_PORT=22
SSH_USER=
SSH_PASSWORD=
APP_PORT=2026
IMAGE_TAG=myagent
RUNTIME_MODE=standard
PUSH_REGISTRY_HOST=101.201.37.112:5000
DEPLOY_REGISTRY_HOST=127.0.0.1:5000
REGISTRY_USER=admin
REGISTRY_PASSWORD=d92RzHUfYgy7Yi9Pop0WUg

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      SSH_PORT="$2"
      shift 2
      ;;
    --user)
      SSH_USER="$2"
      shift 2
      ;;
    --password)
      SSH_PASSWORD="$2"
      shift 2
      ;;
    --app-port)
      APP_PORT="$2"
      shift 2
      ;;
    --tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    --runtime-mode)
      RUNTIME_MODE="$2"
      shift 2
      ;;
    --push-registry-host)
      PUSH_REGISTRY_HOST="$2"
      shift 2
      ;;
    --deploy-registry-host)
      DEPLOY_REGISTRY_HOST="$2"
      shift 2
      ;;
    --registry-user)
      REGISTRY_USER="$2"
      shift 2
      ;;
    --registry-password)
      REGISTRY_PASSWORD="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

[[ -n "$HOST" ]] || { usage >&2; exit 1; }
[[ -n "$SSH_USER" ]] || { usage >&2; exit 1; }
[[ -n "$SSH_PASSWORD" ]] || { usage >&2; exit 1; }

case "$RUNTIME_MODE" in
  standard|gateway) ;;
  *)
    printf 'Invalid runtime mode: %s\n' "$RUNTIME_MODE" >&2
    exit 1
    ;;
esac

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd docker
need_cmd ssh
need_cmd scp
need_cmd sshpass

ensure_docker_available() {
  if ! docker version >/dev/null 2>&1; then
    printf 'Docker daemon is not healthy or not reachable from this shell. Please check Docker Desktop / docker context before running release-ecs.sh.\n' >&2
    exit 1
  fi
}

[[ -n "$PUSH_REGISTRY_HOST" ]] || { printf 'Push registry host is required\n' >&2; exit 1; }
[[ -n "$DEPLOY_REGISTRY_HOST" ]] || { printf 'Deploy registry host is required\n' >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUSH_BACKEND_IMAGE="${PUSH_REGISTRY_HOST}/deerflow-backend:${IMAGE_TAG}"
PUSH_FRONTEND_IMAGE="${PUSH_REGISTRY_HOST}/deerflow-frontend:${IMAGE_TAG}"
FRONTEND_VERSION="$(python3 - <<'PY'
import json
from pathlib import Path
print(json.loads(Path('frontend/package.json').read_text())['version'])
PY
)"
BUILD_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
BUILD_BRANCH="$(git branch --show-current 2>/dev/null || printf 'unknown')"
BUILD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
BUILD_COMMIT_MESSAGE="$(git log -1 --format=%s 2>/dev/null || printf 'unknown')"
BACKEND_BUILD_INFO_FILE="$REPO_ROOT/backend/build_info.json"

log() {
  printf '[release-ecs] %s\n' "$*"
}

write_build_metadata_file() {
  python3 - <<PY
import json
from pathlib import Path
path = Path(r"$BACKEND_BUILD_INFO_FILE")
path.write_text(json.dumps({
    "version": "$FRONTEND_VERSION",
    "build_time": "$BUILD_TIME",
    "branch": "$BUILD_BRANCH",
    "commit": "$BUILD_COMMIT",
    "commit_message": "$BUILD_COMMIT_MESSAGE",
}, ensure_ascii=True, indent=2) + "\n")
print(path)
PY
}

cleanup_build_metadata_file() {
  rm -f "$BACKEND_BUILD_INFO_FILE"
}

build_images() {
  trap cleanup_build_metadata_file RETURN
  write_build_metadata_file >/dev/null
  log "Building backend image ${PUSH_BACKEND_IMAGE}"
  docker build \
    --platform linux/amd64 \
    -t "deerflow-backend:${IMAGE_TAG}" \
    -f "$REPO_ROOT/backend/Dockerfile" \
    "$REPO_ROOT"

  log "Building frontend image ${PUSH_FRONTEND_IMAGE}"
  docker build \
    --platform linux/amd64 \
    --build-arg NEXT_PUBLIC_FRONTEND_VERSION="$FRONTEND_VERSION" \
    --build-arg NEXT_PUBLIC_FRONTEND_BUILD_TIME="$BUILD_TIME" \
    --build-arg NEXT_PUBLIC_FRONTEND_BUILD_BRANCH="$BUILD_BRANCH" \
    --build-arg NEXT_PUBLIC_FRONTEND_BUILD_COMMIT="$BUILD_COMMIT" \
    --build-arg NEXT_PUBLIC_FRONTEND_BUILD_COMMIT_MESSAGE="$BUILD_COMMIT_MESSAGE" \
    -t "deerflow-frontend:${IMAGE_TAG}" \
    -f "$REPO_ROOT/frontend/Dockerfile" \
    --target prod \
    "$REPO_ROOT"
}

tag_images() {
  log "Tagging images for registry ${PUSH_REGISTRY_HOST}"
  docker tag "deerflow-backend:${IMAGE_TAG}" "$PUSH_BACKEND_IMAGE"
  docker tag "deerflow-frontend:${IMAGE_TAG}" "$PUSH_FRONTEND_IMAGE"
}

push_images() {
  log "Logging in to push registry ${PUSH_REGISTRY_HOST}"
  printf '%s' "$REGISTRY_PASSWORD" | docker login "$PUSH_REGISTRY_HOST" --username "$REGISTRY_USER" --password-stdin

  log "Pushing backend image"
  docker push "$PUSH_BACKEND_IMAGE"

  log "Pushing frontend image"
  docker push "$PUSH_FRONTEND_IMAGE"
}

deploy_remote() {
  log "Deploying tag ${IMAGE_TAG} to ECS ${HOST}"
  bash "$REPO_ROOT/scripts/deploy-ecs.sh" \
    --host "$HOST" \
    --port "$SSH_PORT" \
    --user "$SSH_USER" \
    --password "$SSH_PASSWORD" \
    --app-port "$APP_PORT" \
    --tag "$IMAGE_TAG" \
    --runtime-mode "$RUNTIME_MODE" \
    --registry-host "$DEPLOY_REGISTRY_HOST" \
    --registry-user "$REGISTRY_USER" \
    --registry-password "$REGISTRY_PASSWORD"
}

verify_public_health() {
  log "Verifying public health endpoints"
  curl -fsSI "http://${HOST}:${APP_PORT}" >/dev/null
  curl -fsS "http://${HOST}:${APP_PORT}/api/models" >/dev/null
}

main() {
  ensure_docker_available
  build_images
  tag_images
  push_images
  deploy_remote
  verify_public_health
  log "Release completed successfully"
}

main "$@"
