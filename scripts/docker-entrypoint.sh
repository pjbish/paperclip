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

# Always ensure /paperclip is owned by node (Railway volume mounts override build-time ownership)
chown node:node /paperclip

# Configure Git to use GitHub CLI as credential helper when GH_TOKEN is available
if [ -n "$GH_TOKEN" ]; then
    gosu node git config --global credential.helper '!gh auth git-credential'
    echo "Git credential helper configured (gh auth)"
fi

# Configure Xero MCP server for OpenCode agents when Xero credentials are available
if [ -n "$XERO_CLIENT_ID" ] && [ -n "$XERO_CLIENT_SECRET" ]; then
    mkdir -p /paperclip/.config/opencode
    cat > /paperclip/.config/opencode/opencode.json <<XEOF
{
  "mcp": {
    "xero": {
      "type": "local",
      "command": ["npx", "-y", "github:pjbish/xero-mcp-server"],
      "environment": {
        "XERO_CLIENT_ID": "${XERO_CLIENT_ID}",
        "XERO_CLIENT_SECRET": "${XERO_CLIENT_SECRET}"
      }
    }
  }
}
XEOF
    chown -R node:node /paperclip/.config
    echo "Xero MCP server configured for OpenCode agents"
fi

exec gosu node "$@"
