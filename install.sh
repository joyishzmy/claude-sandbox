#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
. "$HERE/scripts/common.sh"

for command_name in docker python3; do
  command -v "$command_name" >/dev/null || { echo "Missing required command: $command_name" >&2; exit 1; }
done

if [ ! -f "$SANDBOX_ROOT/.env" ]; then
  cp "$SANDBOX_ROOT/.env.example" "$SANDBOX_ROOT/.env"
  # Keep the host user's ownership for files written by the container.
  sed -i.bak "s/^SANDBOX_UID=.*/SANDBOX_UID=$(id -u)/; s/^SANDBOX_GID=.*/SANDBOX_GID=$(id -g)/" "$SANDBOX_ROOT/.env"
  rm -f "$SANDBOX_ROOT/.env.bak"
  echo "Created .env with host UID:GID $(id -u):$(id -g)."
fi
# Reload values written above.
. "$HERE/scripts/common.sh"

mkdir -p "$SANDBOX_WORKSPACE" "$SANDBOX_STATE_DIR/gateway" "$SANDBOX_STATE_DIR/home"
chmod 700 "$SANDBOX_STATE_DIR" "$SANDBOX_STATE_DIR/gateway" "$SANDBOX_STATE_DIR/home"

sandbox_ensure_docker
echo "Building the sandbox image..."
sandbox_compose build

if [ ! -f "$SANDBOX_STATE_DIR/gateway/proxies.yaml" ] || [ ! -s "$SANDBOX_STATE_DIR/gateway/proxies.yaml" ]; then
  if verge="$(sandbox_verge_dir)"; then
    echo "Importing US nodes from Clash Verge: $verge"
    sandbox_node_runner "$verge" refresh
  else
    cat >&2 <<'EOF'
No Clash Verge profile was found.
Select your subscription in Verge and rerun ./sandbox refresh, or import a
Clash/mihomo YAML file with ./sandbox import /path/to/config.yaml.
EOF
    exit 1
  fi
fi

sandbox_compose up -d
bash "$HERE/scripts/verify.sh"
echo
echo "Ready. Run ./sandbox to enter, or ./sandbox install-claude to install Claude Code."
