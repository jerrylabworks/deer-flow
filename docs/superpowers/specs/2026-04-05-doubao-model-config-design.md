# Doubao Model Config Design

**Goal:** Enable DeerFlow to use the Volcengine Doubao model `doubao-seed-1-8-251228` via `config.yaml` with an environment-variable API key.

**Scope:** Update only `config.yaml` to add a single model entry under `models`. No code changes, no new dependencies.

**Assumptions:**
- The user provides `VOLCENGINE_API_KEY` in the shell environment used for `make docker-start`.
- Docker development flow is used.

## Architecture

DeerFlow reads `config.yaml` at runtime to discover available models. We will add a Doubao model entry that uses the existing Volcengine example shape, with `api_base` set to `https://ark.cn-beijing.volces.com/api/v3` and `api_key` referencing `$VOLCENGINE_API_KEY`. This keeps configuration aligned with documented examples and avoids storing secrets in the repo.

## Data Flow

1. `make docker-start` launches DeerFlow services.
2. DeerFlow loads `config.yaml`.
3. The model registry reads the Doubao entry and resolves `$VOLCENGINE_API_KEY` from the environment.

## Error Handling

- If `VOLCENGINE_API_KEY` is missing, the model initialization will fail; the user must provide the env var.
- If the model name or api_base is incorrect, model calls will fail; use the specified `doubao-seed-1-8-251228` id and official API base.

## Testing

No automated tests are required. Manual validation is limited to starting services and invoking the model after configuration.

## Files

- Modify: `config.yaml`
