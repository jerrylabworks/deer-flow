#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-ecs.sh --host HOST --user USER --password PASS [options]

Options:
  --host HOST                  ECS public IP or hostname
  --port PORT                  SSH port (default: 22)
  --user USER                  SSH login user
  --password PASS              SSH password
  --app-port PORT              DeerFlow exposed port on ECS (default: 2026)
  --tag TAG                    Registry tag (default: myagent)
  --runtime-mode MODE          standard or gateway (default: standard)
  --deploy-dir DIR             Remote deployment directory (default: /opt/deer-flow)
  --registry-host HOST:PORT    Registry host (default: 127.0.0.1:5000)
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
DEPLOY_DIR=/opt/deer-flow
REGISTRY_HOST=127.0.0.1:5000
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
    --deploy-dir)
      DEPLOY_DIR="$2"
      shift 2
      ;;
    --registry-host)
      REGISTRY_HOST="$2"
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

need_cmd ssh
need_cmd scp
need_cmd sshpass

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_IMAGE="${REGISTRY_HOST}/deerflow-backend:${IMAGE_TAG}"
FRONTEND_IMAGE="${REGISTRY_HOST}/deerflow-frontend:${IMAGE_TAG}"
SSH_BASE=(sshpass -p "$SSH_PASSWORD")
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT")
SCP_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$SSH_PORT")
REMOTE="${SSH_USER}@${HOST}"

log() {
  printf '[deploy-ecs] %s\n' "$*"
}

upload_file() {
  local src="$1"
  local dst="$2"
  sshpass -p "$SSH_PASSWORD" scp "${SCP_OPTS[@]}" "$src" "$REMOTE:$dst"
}

run_remote() {
  "${SSH_BASE[@]}" ssh "${SSH_OPTS[@]}" "$REMOTE" "$@"
}

log "Preparing remote directory ${DEPLOY_DIR}"
run_remote "mkdir -p '$DEPLOY_DIR' '$DEPLOY_DIR/docker/nginx' '$DEPLOY_DIR/frontend' '$DEPLOY_DIR/scripts' '$DEPLOY_DIR/backend/.deer-flow' '$DEPLOY_DIR/backend/.langgraph_api' '$DEPLOY_DIR/skills'"

log "Uploading deployment assets"
upload_file "$REPO_ROOT/scripts/remote-deploy.sh" "$DEPLOY_DIR/scripts/remote-deploy.sh"
upload_file "$REPO_ROOT/docker/docker-compose.registry.yaml" "$DEPLOY_DIR/docker/docker-compose.registry.yaml"
upload_file "$REPO_ROOT/docker/nginx/nginx.conf" "$DEPLOY_DIR/docker/nginx/nginx.conf"
upload_file "$REPO_ROOT/config.yaml" "$DEPLOY_DIR/config.yaml"
upload_file "$REPO_ROOT/extensions_config.json" "$DEPLOY_DIR/extensions_config.json"
upload_file "$REPO_ROOT/.env" "$DEPLOY_DIR/.env"
upload_file "$REPO_ROOT/frontend/.env" "$DEPLOY_DIR/frontend/.env"

log "Syncing support directories"
run_remote "rm -rf '$DEPLOY_DIR/skills' '$DEPLOY_DIR/backend/.langgraph_api' && mkdir -p '$DEPLOY_DIR/skills' '$DEPLOY_DIR/backend/.langgraph_api'"
sshpass -p "$SSH_PASSWORD" scp "${SCP_OPTS[@]}" -r "$REPO_ROOT/skills/." "$REMOTE:$DEPLOY_DIR/skills/"
sshpass -p "$SSH_PASSWORD" scp "${SCP_OPTS[@]}" -r "$REPO_ROOT/backend/.langgraph_api/." "$REMOTE:$DEPLOY_DIR/backend/.langgraph_api/"

log "Running remote deployment"
run_remote "chmod +x '$DEPLOY_DIR/scripts/remote-deploy.sh' && '$DEPLOY_DIR/scripts/remote-deploy.sh' --deploy-dir '$DEPLOY_DIR' --app-port '$APP_PORT' --backend-image '$BACKEND_IMAGE' --frontend-image '$FRONTEND_IMAGE' --registry-host '$REGISTRY_HOST' --registry-user '$REGISTRY_USER' --registry-password '$REGISTRY_PASSWORD' --runtime-mode '$RUNTIME_MODE'"

log "Deployment completed"
log "Expected application URL: http://${HOST}:${APP_PORT}"
