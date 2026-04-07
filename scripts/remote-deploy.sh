#!/usr/bin/env bash

set -euo pipefail

log() {
  printf '[remote-deploy] %s\n' "$*"
}

fail() {
  printf '[remote-deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: remote-deploy.sh --deploy-dir DIR --app-port PORT --backend-image IMAGE --frontend-image IMAGE --registry-host HOST --registry-user USER --registry-password PASS [--runtime-mode standard|gateway]
EOF
}

DEPLOY_DIR=
APP_PORT=2026
BACKEND_IMAGE=
FRONTEND_IMAGE=
REGISTRY_HOST=
REGISTRY_USER=
REGISTRY_PASSWORD=
RUNTIME_MODE=standard

while [[ $# -gt 0 ]]; do
  case "$1" in
    --deploy-dir)
      DEPLOY_DIR="$2"
      shift 2
      ;;
    --app-port)
      APP_PORT="$2"
      shift 2
      ;;
    --backend-image)
      BACKEND_IMAGE="$2"
      shift 2
      ;;
    --frontend-image)
      FRONTEND_IMAGE="$2"
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
    --runtime-mode)
      RUNTIME_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$DEPLOY_DIR" ]] || fail "--deploy-dir is required"
[[ -n "$BACKEND_IMAGE" ]] || fail "--backend-image is required"
[[ -n "$FRONTEND_IMAGE" ]] || fail "--frontend-image is required"
[[ -n "$REGISTRY_HOST" ]] || fail "--registry-host is required"
[[ -n "$REGISTRY_USER" ]] || fail "--registry-user is required"
[[ -n "$REGISTRY_PASSWORD" ]] || fail "--registry-password is required"

ensure_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "Please run remote deployment as root on the ECS host"
  fi
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  if ! apt-get update; then
    rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list
    apt-get update
  fi
  apt-get install -y "$@"
}

ensure_packages() {
  log "Installing base packages"
  apt_install ca-certificates curl gnupg lsb-release openssl
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and compose plugin already installed"
    return
  fi

  log "Installing Docker Engine and compose plugin"
  rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl restart docker
}

wait_for_docker() {
  local attempt=0
  until docker info >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ "$attempt" -ge 30 ]]; then
      fail "Docker daemon did not become ready in time"
    fi
    sleep 2
  done
}

install_registry_cert() {
  local cert_dir="/etc/docker/certs.d/${REGISTRY_HOST}"
  mkdir -p "$cert_dir"
  log "Installing registry certificate for ${REGISTRY_HOST}"
  openssl s_client -showcerts -connect "$REGISTRY_HOST" -servername "${REGISTRY_HOST%%:*}" </dev/null 2>/dev/null | openssl x509 -outform PEM > "$cert_dir/ca.crt"
  systemctl restart docker
  wait_for_docker
}

docker_login_registry() {
  log "Logging in to private registry ${REGISTRY_HOST}"
  printf '%s' "$REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" --username "$REGISTRY_USER" --password-stdin
}

ensure_runtime_layout() {
  log "Preparing deployment directory ${DEPLOY_DIR}"
  mkdir -p "$DEPLOY_DIR" "$DEPLOY_DIR/backend/.deer-flow" "$DEPLOY_DIR/frontend" "$DEPLOY_DIR/docker/nginx" "$DEPLOY_DIR/skills" "$DEPLOY_DIR/backend/.langgraph_api"
}

ensure_runtime_files() {
  [[ -f "$DEPLOY_DIR/config.yaml" ]] || fail "Missing $DEPLOY_DIR/config.yaml"
  [[ -f "$DEPLOY_DIR/extensions_config.json" ]] || fail "Missing $DEPLOY_DIR/extensions_config.json"
  [[ -f "$DEPLOY_DIR/.env" ]] || fail "Missing $DEPLOY_DIR/.env"
  [[ -f "$DEPLOY_DIR/frontend/.env" ]] || fail "Missing $DEPLOY_DIR/frontend/.env"
  [[ -f "$DEPLOY_DIR/docker/docker-compose.registry.yaml" ]] || fail "Missing registry compose file"
  [[ -f "$DEPLOY_DIR/docker/nginx/nginx.conf" ]] || fail "Missing nginx config"
}

ensure_auth_secret() {
  local secret_file="$DEPLOY_DIR/backend/.deer-flow/.better-auth-secret"
  if [[ ! -f "$secret_file" ]]; then
    log "Generating BETTER_AUTH_SECRET"
    python3 - <<'PY' > "$secret_file"
import secrets
print(secrets.token_hex(32))
PY
    chmod 600 "$secret_file"
  fi

  python3 - <<'PY' "$DEPLOY_DIR/.env" "$secret_file"
from pathlib import Path
import sys

env_path = Path(sys.argv[1])
secret = Path(sys.argv[2]).read_text().strip()
lines = env_path.read_text().splitlines()
updated = False
for i, line in enumerate(lines):
    if line.startswith('BETTER_AUTH_SECRET='):
        lines[i] = f'BETTER_AUTH_SECRET={secret}'
        updated = True
        break
if not updated:
    if lines and lines[-1] != '':
        lines.append('')
    lines.append(f'BETTER_AUTH_SECRET={secret}')
env_path.write_text('\n'.join(lines) + '\n')
PY
}

deploy_stack() {
  local compose_file="$DEPLOY_DIR/docker/docker-compose.registry.yaml"
  local backend_image="$BACKEND_IMAGE"
  local frontend_image="$FRONTEND_IMAGE"
  local langgraph_upstream="langgraph:2024"
  local langgraph_rewrite='/'
  local services=(frontend gateway langgraph nginx)

  if [[ "$RUNTIME_MODE" == "gateway" ]]; then
    langgraph_upstream='gateway:8001'
    langgraph_rewrite='/api/'
    services=(frontend gateway nginx)
  fi

  log "Pulling images"
  (
    cd "$DEPLOY_DIR"
    export HOME=/root
    export PORT="$APP_PORT"
    export DEER_FLOW_HOME="$DEPLOY_DIR/backend/.deer-flow"
    export DEER_FLOW_CONFIG_PATH="$DEPLOY_DIR/config.yaml"
    export DEER_FLOW_EXTENSIONS_CONFIG_PATH="$DEPLOY_DIR/extensions_config.json"
    export DEER_FLOW_DOCKER_SOCKET=/var/run/docker.sock
    export DEER_FLOW_REPO_ROOT="$DEPLOY_DIR"
    export DEER_FLOW_BACKEND_IMAGE="$backend_image"
    export DEER_FLOW_FRONTEND_IMAGE="$frontend_image"
    export LANGGRAPH_UPSTREAM="$langgraph_upstream"
    export LANGGRAPH_REWRITE="$langgraph_rewrite"
    export BETTER_AUTH_SECRET="$(cat "$DEPLOY_DIR/backend/.deer-flow/.better-auth-secret")"
    docker compose -p deer-flow -f "$compose_file" pull "${services[@]}"
    docker compose -p deer-flow -f "$compose_file" up -d --remove-orphans "${services[@]}"
  )
}

health_check() {
  local compose_file="$DEPLOY_DIR/docker/docker-compose.registry.yaml"

  log "Waiting for services to settle"
  sleep 10

  if ! curl -fsS "http://127.0.0.1:${APP_PORT}/" >/dev/null; then
    log "Root endpoint failed, printing diagnostics"
    (
      cd "$DEPLOY_DIR"
      export HOME=/root
      export PORT="$APP_PORT"
      export DEER_FLOW_HOME="$DEPLOY_DIR/backend/.deer-flow"
      export DEER_FLOW_CONFIG_PATH="$DEPLOY_DIR/config.yaml"
      export DEER_FLOW_EXTENSIONS_CONFIG_PATH="$DEPLOY_DIR/extensions_config.json"
      export DEER_FLOW_DOCKER_SOCKET=/var/run/docker.sock
      export DEER_FLOW_REPO_ROOT="$DEPLOY_DIR"
      export DEER_FLOW_BACKEND_IMAGE="$BACKEND_IMAGE"
      export DEER_FLOW_FRONTEND_IMAGE="$FRONTEND_IMAGE"
      export BETTER_AUTH_SECRET="$(cat "$DEPLOY_DIR/backend/.deer-flow/.better-auth-secret")"
      docker compose -p deer-flow -f "$compose_file" ps
      docker compose -p deer-flow -f "$compose_file" logs --tail=100 frontend gateway langgraph nginx
    )
    fail "Root endpoint check failed"
  fi

  if ! curl -fsS "http://127.0.0.1:${APP_PORT}/api/models" >/dev/null; then
    fail "API models endpoint check failed"
  fi

  log "Deployment succeeded: http://127.0.0.1:${APP_PORT}"
}

main() {
  ensure_root
  ensure_packages
  ensure_docker
  wait_for_docker
  install_registry_cert
  docker_login_registry
  ensure_runtime_layout
  ensure_runtime_files
  ensure_auth_secret
  deploy_stack
  health_check
}

main "$@"
