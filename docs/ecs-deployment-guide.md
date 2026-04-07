# DeerFlow ECS Deployment Guide

This guide explains how to deploy DeerFlow to an Alibaba Cloud ECS instance running Ubuntu 22.04 by using the one-click deployment script and the private Docker registry.

## Overview

The deployment flow uses these files:

- `scripts/deploy-ecs.sh` — run locally from your workstation
- `scripts/remote-deploy.sh` — uploaded and run on the ECS host
- `docker/docker-compose.registry.yaml` — production stack using registry images

Default assumptions:

- ECS OS: Ubuntu 22.04
- Deployment directory: `/opt/deer-flow`
- Registry: `127.0.0.1:5000`
- Default image tag: `myagent`
- Default application port: `2026`

## Local Prerequisites

Install these tools on your local machine before running the deploy script:

- `ssh`
- `scp`
- `sshpass`

The local repository must also contain the runtime files you want to upload:

- `config.yaml`
- `.env`
- `frontend/.env`
- `extensions_config.json`

## ECS Network Requirements

Make sure the ECS security group allows these inbound ports:

- `22/tcp` for SSH
- `2026/tcp` for DeerFlow web access

If you change the app port with `--app-port`, open that port instead.

## What the Script Does

When you run `scripts/deploy-ecs.sh`, it will:

1. Validate local tools and required arguments
2. Connect to ECS over SSH using password authentication
3. Upload deployment files to `/opt/deer-flow`
4. Install Docker and Docker Compose plugin on Ubuntu 22.04 if needed
5. Trust the private registry self-signed certificate
6. Log into the private registry
7. Pull the requested DeerFlow images
8. Start the application stack
9. Verify `http://127.0.0.1:<port>/` and `http://127.0.0.1:<port>/api/models`

## First-Time Deployment

Run this from the repository root on your local machine:

```bash
chmod +x scripts/deploy-ecs.sh scripts/remote-deploy.sh

./scripts/deploy-ecs.sh \
  --host <ecs-public-ip> \
  --user root \
  --password '<ecs-ssh-password>'
```

On success, the script prints the expected access URL:

```bash
http://<ecs-public-ip>:2026
```

## Deploy a Specific Image Tag

To deploy a different registry tag:

```bash
./scripts/deploy-ecs.sh \
  --host <ecs-public-ip> \
  --user root \
  --password '<ecs-ssh-password>' \
  --tag 0bdaf8db
```

## Use Gateway Mode

To deploy without the separate LangGraph service:

```bash
./scripts/deploy-ecs.sh \
  --host <ecs-public-ip> \
  --user root \
  --password '<ecs-ssh-password>' \
  --runtime-mode gateway
```

## Files on the Server

After deployment, the main server-side files live under `/opt/deer-flow`:

- `/opt/deer-flow/.env`
- `/opt/deer-flow/config.yaml`
- `/opt/deer-flow/extensions_config.json`
- `/opt/deer-flow/docker/docker-compose.registry.yaml`
- `/opt/deer-flow/backend/.deer-flow`

## Check Deployment Status on ECS

SSH into the server and run:

```bash
cd /opt/deer-flow

export PORT=2026
export DEER_FLOW_HOME=/opt/deer-flow/backend/.deer-flow
export DEER_FLOW_CONFIG_PATH=/opt/deer-flow/config.yaml
export DEER_FLOW_EXTENSIONS_CONFIG_PATH=/opt/deer-flow/extensions_config.json
export DEER_FLOW_DOCKER_SOCKET=/var/run/docker.sock
export DEER_FLOW_REPO_ROOT=/opt/deer-flow
export DEER_FLOW_BACKEND_IMAGE=101.201.37.112:5000/deerflow-backend:myagent
export DEER_FLOW_FRONTEND_IMAGE=101.201.37.112:5000/deerflow-frontend:myagent
export BETTER_AUTH_SECRET=$(cat /opt/deer-flow/backend/.deer-flow/.better-auth-secret)

docker compose -p deer-flow -f docker/docker-compose.registry.yaml ps
docker compose -p deer-flow -f docker/docker-compose.registry.yaml logs --tail=100 frontend gateway langgraph nginx
```

## Restart Services on ECS

```bash
cd /opt/deer-flow

docker compose -p deer-flow -f docker/docker-compose.registry.yaml restart
```

## Pull Updated Images and Redeploy

Re-run the local deployment script with the same or a new tag. The script will pull fresh images and restart the stack.

## Troubleshooting

### SSH login fails

- Confirm ECS password login is enabled
- Confirm the security group allows `22/tcp`
- Confirm the username is correct, usually `root` or your admin user

### Registry login fails

- Confirm the registry container is running on ECS
- Confirm `127.0.0.1:5000` is reachable from the ECS host
- Confirm the registry credentials are still valid

### Docker cannot trust the registry certificate

The remote script installs the certificate automatically under:

```bash
/etc/docker/certs.d/127.0.0.1:5000/ca.crt
```

If needed, rerun the deployment script after checking server connectivity to the registry host.

### Containers start but the site is unavailable

On ECS, run:

```bash
curl -I http://127.0.0.1:2026
curl -I http://127.0.0.1:2026/api/models
docker compose -p deer-flow -f /opt/deer-flow/docker/docker-compose.registry.yaml logs --tail=100 frontend gateway langgraph nginx
```

### API keys or model config are wrong

Edit these files on the server and redeploy or restart:

- `/opt/deer-flow/.env`
- `/opt/deer-flow/config.yaml`

## Notes

- This workflow uploads the current local runtime config to ECS, including `.env`, so treat your local machine as a deployment control host.
- The script is designed for a single-server deployment, not a clustered environment.
- Password-based SSH works, but private-key-based SSH is safer for long-term use.
