# Doubao Model Config Design

**Goal:** Enable DeerFlow to use the Volcengine Doubao model `doubao-seed-1-8-251228` via `config.yaml` with an environment-variable API key.

**Scope:** Update only `config.yaml` to add a single Doubao model entry under `models`. No code changes, no new dependencies.

**Assumptions:**
- The user provides `VOLCENGINE_API_KEY` in the environment passed to the Docker containers (exported in the shell before `make docker-start` or defined in the compose `.env`).
- Docker development flow is used.
- The Doubao model entry is placed first in `models` so it becomes the default model (or the user explicitly selects it by name in the UI/API).

## Architecture

DeerFlow reads `config.yaml` at runtime to discover available models. We will add a Doubao model entry using the existing Volcengine example shape, including required fields and capability flags. This keeps configuration aligned with documented examples and avoids storing secrets in the repo.

Example entry (add this item under the existing `models:` list):

```yaml
  - name: doubao-seed-1.8
    display_name: Doubao-Seed-1.8
    use: deerflow.models.patched_deepseek:PatchedChatDeepSeek
    model: doubao-seed-1-8-251228
    api_base: https://ark.cn-beijing.volces.com/api/v3
    api_key: $VOLCENGINE_API_KEY
    timeout: 600.0
    max_retries: 2
    supports_thinking: true
    supports_vision: true
    when_thinking_enabled:
      extra_body:
        thinking:
          type: enabled
```

## Data Flow

1. `make docker-start` launches DeerFlow services.
2. DeerFlow loads `config.yaml`.
3. The model registry reads the Doubao entry and resolves `$VOLCENGINE_API_KEY` from the container environment.

## Error Handling

- If `VOLCENGINE_API_KEY` is missing from the container environment, model initialization will fail; the user must provide the env var via shell export or compose `.env`.
- If the model name or api_base is incorrect, model calls will fail; use the specified `doubao-seed-1-8-251228` id and official API base.
- If the model is not first in the list and no explicit model is selected, DeerFlow may default to another model; order or selection must be intentional.

## Testing

No automated tests are required. Manual validation is limited to:
- Start services: `make docker-start`
- Confirm the model appears in the UI/models list and can be selected by `name: doubao-seed-1.8`.

## Files

- Modify: `config.yaml`
