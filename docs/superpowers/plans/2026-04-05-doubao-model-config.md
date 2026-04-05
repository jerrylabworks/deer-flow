I'm using the writing-plans skill to create the implementation plan.

# Doubao Model Config Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Doubao model entry to `config.yaml` so DeerFlow can use `doubao-seed-1-8-251228` via `$VOLCENGINE_API_KEY`.

**Architecture:** Configuration-only change. Add a single model entry under `models` in `config.yaml`, aligned with the Volcengine example. No code changes or new dependencies.

**Tech Stack:** YAML config, Docker dev flow.

---

## File Structure

- `config.yaml` — main runtime configuration for models, tools, and sandbox settings. We will append a Doubao model entry under `models`.

---

### Task 1: Add Doubao model entry to config.yaml

**Files:**
- Modify: `config.yaml`

- [ ] **Step 1: Write the failing test (N/A)**

This change is configuration-only. No automated tests are required per spec.

- [ ] **Step 2: Run test to verify it fails (N/A)**

No automated test to run.

- [ ] **Step 3: Write minimal implementation**

Place the Doubao model entry first under the existing `models:` list so it becomes the default model. Add the following item (do not replace the list):

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

- [ ] **Step 4: Run test to verify it passes (manual verification)**

Run: `make docker-start`

Expected: services start without config errors.

Run: open `http://localhost:2026` and check the model selector (or query `GET /api/models` via the Gateway) for `doubao-seed-1.8`.

Expected: `doubao-seed-1.8` appears and can be selected by name.

- [ ] **Step 5: Commit**

```bash
git add config.yaml
git commit -m "chore: add Doubao model config"
```
