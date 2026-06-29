# router/oauth-guide.md — 9router Dashboard Setup Guide

## Overview

9router is a local proxy daemon at `http://localhost:20128`. It sits between
skeleton and the actual AI provider (Claude, Copilot, OpenAI). Instead of
calling `api.anthropic.com` directly, skeleton calls `localhost:20128/v1` and
9router forwards the request using the API key you configure here.

**Dashboard:** `http://localhost:20128/dashboard`

---

## How the Dashboard is Organized

| Section | What it does |
|---------|-------------|
| **Providers** | Where you add AI providers and enter their API keys |
| **Combos** | Named groups of providers — skeleton references this by name |
| **Endpoint & Key** | Shows the local URL skeleton uses (`http://localhost:20128/v1`) |
| **Usage** | Request logs, token counts, cost tracking |

**The setup order is always:** Providers → Combos → create `inject-env.sh`

---

## Prerequisites

9router installed and running:

```sh
skeleton router install
skeleton router start
skeleton router status   # verify: Running: yes, Health: OK
```

Open the 9router dashboard: `http://localhost:20128/dashboard`

---

## Provider A — Anthropic Claude

### 1. Add Claude as a Provider

Dashboard → sidebar **Providers** → **+ Add** → choose **Claude**

Enter your Anthropic API key (get it from https://console.anthropic.com):

```
sk-ant-api03-...
```

Click **Save**. 9router stores the key internally and uses it to forward requests.

### 2. Create a Combo

Dashboard → sidebar **Combos** → **+ Create**

- **Name:** `project-default`
- Add the Claude provider you just created
- Click **Save**

A combo is a named routing group. `config/skeleton.yaml` references it by name.
You can add multiple providers to a combo for fallback/round-robin later.

### 3. Note the Endpoint

Dashboard → sidebar **Endpoint & Key**

You'll see:
```
API Endpoint: http://localhost:20128/v1
```

This is `ANTHROPIC_BASE_URL` — the address skeleton uses instead of `api.anthropic.com`.

### 4. Create `router/inject-env.sh`

In your project directory:

```bash
mkdir -p router
cat > router/inject-env.sh << 'EOF'
export ANTHROPIC_BASE_URL="http://localhost:20128/v1"
export ANTHROPIC_API_KEY="sk-ant-your-actual-key-here"
EOF
chmod 600 router/inject-env.sh
```

> **Why does `ANTHROPIC_API_KEY` still need a value?** The Claude CLI must send
> something in the `Authorization` header or it refuses to start. Since
> "Require API key" is OFF in 9router, 9router ignores this value — but the
> header must be present. Set it to your real Anthropic key.

---

## Provider B — GitHub Copilot

### 1. Add Copilot as a Provider

Dashboard → sidebar **Providers** → **+ Add** → choose **GitHub Copilot**

Click **Authorize with GitHub** and complete the OAuth flow in your browser.
After authorization, 9router stores the GitHub token.

### 2. Create or Update a Combo

Dashboard → **Combos** → add Copilot to your existing combo, or create a new one:

- **Name:** `project-copilot`
- Add the GitHub Copilot provider → **Save**

### 3. Create `router/inject-env.sh`

```bash
# router/inject-env.sh
export COPILOT_PROXY_URL="http://localhost:20128/v1"
# ANTHROPIC_API_KEY not needed for Copilot-only setups
```

Update `config/skeleton.yaml`:

```yaml
router:
  combo: project-copilot
```

---

## Provider C — OpenAI / Codex

### 1. Add OpenAI as a Provider

Dashboard → sidebar **Providers** → **+ Add** → choose **OpenAI**

Enter your OpenAI API key (from https://platform.openai.com/api-keys).

### 2. Create a Combo

Dashboard → **Combos** → **+ Create** → name `project-openai` → add OpenAI → **Save**

### 3. Create `router/inject-env.sh`

```bash
# router/inject-env.sh
export OPENAI_BASE_URL="http://localhost:20128/v1"
export OPENAI_API_KEY="sk-..."
```

---

## Combo Routing

A combo can hold multiple providers in priority order. 9router tries the first
provider; if it returns a quota/rate-limit error, it falls through to the next.

Example multi-provider combo:
1. Claude (primary)
2. Copilot (fallback if Claude quota exhausted)

Configure this in **Combos** → edit your combo → drag providers to set order.

The active combo is set in `config/skeleton.yaml`:

```yaml
router:
  combo: project-default
```

---

## Verifying the Connection

```bash
skeleton router health              # exit 0 if 9router is up and responding
skeleton auth --provider=9router    # full pre-flight: daemon ✓ + inject-env.sh ✓
```

Test a live request:

```bash
curl http://localhost:20128/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-ant-your-key" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"ping"}]}'
```

---

## Security Notes

- `router/inject-env.sh` may contain API keys — it is `chmod 600` by default
- Never commit `router/inject-env.sh` to source control
- Add to `.gitignore`: `router/inject-env.sh`
- The 9router dashboard is local-only (port 20128) — not exposed to the network

---

## Troubleshooting

| Symptom                   | Fix                                                           |
| ------------------------- | ------------------------------------------------------------- |
| `health check failed`     | Run `skeleton router start`                                   |
| `inject-env.sh not found` | Create it (see steps above)                                   |
| Agent sees 401/403        | Check Anthropic API key is correct in Providers               |
| Port 20128 in use         | Set `NINE_ROUTER_PORT` env var, update `config/skeleton.yaml` |
| 9router not starting      | Check logs: `cat .skeleton-dev/9router.log`                   |
| Dashboard blank/error     | Open `http://localhost:20128/dashboard` (not just `/`)        |
