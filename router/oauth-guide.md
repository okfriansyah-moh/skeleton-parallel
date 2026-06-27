# router/oauth-guide.md — 9router OAuth Connection Guide

## Overview

`skeleton router oauth` sets up OAuth tokens that 9router uses to proxy requests
to your AI provider. After completing OAuth, the tokens are written to
`router/inject-env.sh` which is sourced by CLI drivers before each agent call.

---

## Step-by-Step Setup

### Prerequisites

1. 9router installed and running:

   ```
   skeleton router install
   skeleton router start
   skeleton router status   # verify: Running: yes
   ```

2. Open the 9router dashboard:
   ```
   http://localhost:20128
   ```

---

## Provider A — GitHub Copilot

1. In the 9router dashboard → **Connections** → **Add Provider** → **GitHub Copilot**
2. Click **Authorize with GitHub** and complete the OAuth flow in your browser
3. After authorization, 9router shows a connection token
4. Copy the connection token to `router/inject-env.sh`:

   ```bash
   # router/inject-env.sh
   export COPILOT_PROXY_URL="http://localhost:20128/v1"
   export COPILOT_GITHUB_TOKEN="<token-from-9router-dashboard>"
   ```

5. Restart to apply:
   ```
   skeleton router stop && skeleton router start
   ```

---

## Provider B — Anthropic Claude

1. In the 9router dashboard → **Connections** → **Add Provider** → **Claude**
2. Enter your Anthropic API key (from https://console.anthropic.com)
3. 9router validates the key and assigns a proxy endpoint
4. Copy settings to `router/inject-env.sh`:

   ```bash
   # router/inject-env.sh
   export ANTHROPIC_BASE_URL="http://localhost:20128/v1"
   export ANTHROPIC_API_KEY="<your-anthropic-key>"
   ```

---

## Provider C — OpenAI Codex

1. In the 9router dashboard → **Connections** → **Add Provider** → **OpenAI**
2. Enter your OpenAI API key (from https://platform.openai.com/api-keys)
3. Copy settings to `router/inject-env.sh`:

   ```bash
   # router/inject-env.sh
   export OPENAI_BASE_URL="http://localhost:20128/v1"
   export OPENAI_API_KEY="<your-openai-key>"
   ```

---

## Combo Routing

9router supports routing combos — groups of providers used in round-robin or
priority order. Configure combos in the 9router dashboard under **Combos**.

The active combo is set in `config/skeleton.yaml`:

```yaml
router:
  combo: project-default # name of your combo in 9router dashboard
```

---

## Verifying the Connection

```bash
skeleton router health    # exit 0 if 9router is up and responding
skeleton router status    # prints provider connection details
```

To test a provider:

```bash
curl http://localhost:20128/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4.6","messages":[{"role":"user","content":"ping"}]}'
```

---

## Security Notes

- `router/inject-env.sh` may contain API keys — it is `chmod 600` by default
- Never commit `router/inject-env.sh` to source control
- Add to `.gitignore`: `router/inject-env.sh`
- The 9router dashboard is local-only (port 20128) — not exposed externally

---

## Troubleshooting

| Symptom                   | Fix                                                           |
| ------------------------- | ------------------------------------------------------------- |
| `health check failed`     | Run `skeleton router start`                                   |
| `inject-env.sh not found` | Run `skeleton router install`                                 |
| Agent sees 401/403        | Re-run OAuth for that provider                                |
| Port 20128 in use         | Set `NINE_ROUTER_PORT` env var, update `config/skeleton.yaml` |
| 9router not starting      | Check `skeleton router status`, try `skeleton router install` |
