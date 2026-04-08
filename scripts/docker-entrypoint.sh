#!/bin/sh
set -e

PUID=${USER_UID:-1000}
PGID=${USER_GID:-1000}

if [ "$(id -u node)" -ne "$PUID" ]; then
    echo "Updating node UID to $PUID"
    usermod -o -u "$PUID" node
fi

if [ "$(id -g node)" -ne "$PGID" ]; then
    echo "Updating node GID to $PGID"
    groupmod -o -g "$PGID" node
    usermod -g "$PGID" node
fi

# One-time volume cleanup (remove after Railway migration complete)
if [ -f /paperclip/.needs-cleanup ] || [ "${PAPERCLIP_CLEANUP_ON_BOOT:-}" = "true" ]; then
    echo "Cleaning up logs, backups, and run-logs to free disk space..."
    rm -rf /paperclip/instances/default/logs/* \
           /paperclip/instances/default/data/backups/* \
           /paperclip/instances/default/data/run-logs/* \
           /paperclip/.cache/* 2>/dev/null || true
    rm -f /paperclip/.needs-cleanup
    echo "Cleanup complete"
fi

# Always ensure /paperclip is owned by node (Railway volume mounts override build-time ownership)
chown -R node:node /paperclip

# Ensure Hermes session/config directories exist on the volume
mkdir -p /paperclip/.hermes/sessions /paperclip/.hermes/skills
chown -R node:node /paperclip/.hermes

# Configure Git to use GitHub CLI as credential helper when GH_TOKEN is available
if [ -n "$GH_TOKEN" ]; then
    gosu node git config --global credential.helper '!gh auth git-credential' || echo "WARN: git config failed (non-fatal)"
    echo "Git credential helper configured (gh auth)"
fi

# Configure Composio MCP gateway for all agents (Notion, Xero, etc.)
if [ -n "$COMPOSIO_API_KEY" ]; then
    mkdir -p /paperclip/.config/opencode
    cat > /paperclip/.config/opencode/opencode.json <<XEOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "openrouter": {
      "models": {
        "auto": {
          "name": "OpenRouter Auto",
          "max_tokens": 128000,
          "supports_tool_use": true,
          "supports_object_generation": true
        }
      }
    }
  },
  "mcp": {
    "composio": {
      "type": "remote",
      "url": "https://connect.composio.dev/mcp",
      "headers": {
        "X-CONSUMER-API-KEY": "${COMPOSIO_API_KEY}"
      }
    }
  }
}
XEOF
    chown -R node:node /paperclip/.config
    echo "Composio MCP gateway configured for agents"
fi

exec gosu node "$@"
