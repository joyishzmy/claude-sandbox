#!/usr/bin/env bash
# Shared helpers. Sourced by the CLI and installer; not a standalone command.
SANDBOX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$SANDBOX_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SANDBOX_ROOT/.env"
  set +a
fi
SANDBOX_WORKSPACE="${SANDBOX_WORKSPACE:-$SANDBOX_ROOT/workspace}"
SANDBOX_STATE_DIR="${SANDBOX_STATE_DIR:-$SANDBOX_ROOT/state}"
SANDBOX_TZ="${SANDBOX_TZ:-America/Los_Angeles}"
SANDBOX_LOCALE="${SANDBOX_LOCALE:-en_US.UTF-8}"
SANDBOX_UID="${SANDBOX_UID:-$(id -u)}"
SANDBOX_GID="${SANDBOX_GID:-$(id -g)}"
SANDBOX_GATEWAY=sandbox-gateway
SANDBOX_CONTAINER=sandbox-workspace
SANDBOX_IMAGE=claude-sandbox:latest
export SANDBOX_WORKSPACE SANDBOX_STATE_DIR SANDBOX_TZ SANDBOX_LOCALE
export SANDBOX_UID SANDBOX_GID

sandbox_abspath() {
  python3 -c 'import os, sys; print(os.path.abspath(os.path.join(sys.argv[1], sys.argv[2])))' "$SANDBOX_ROOT" "$1"
}
SANDBOX_WORKSPACE="$(sandbox_abspath "$SANDBOX_WORKSPACE")"
SANDBOX_STATE_DIR="$(sandbox_abspath "$SANDBOX_STATE_DIR")"
export SANDBOX_WORKSPACE SANDBOX_STATE_DIR

sandbox_platform() {
  if [[ "$OSTYPE" == darwin* ]]; then
    echo macos
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo wsl
  else
    echo linux
  fi
}

sandbox_compose() {
  (cd "$SANDBOX_ROOT" && docker compose -f "$SANDBOX_ROOT/docker-compose.yml" "$@")
}

sandbox_ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    return 0
  fi
  case "$(sandbox_platform)" in
    macos)
      open -a Docker >/dev/null 2>&1 || open -a "Docker Desktop" >/dev/null 2>&1 || true
      ;;
    wsl)
      local desktop=""
      for candidate in \
        "/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe" \
        /mnt/c/Users/*/AppData/Local/Programs/DockerDesktop/"Docker Desktop.exe"; do
        if [ -f "$candidate" ]; then
          desktop="$candidate"
          break
        fi
      done
      if [ -n "$desktop" ]; then
        (cd /mnt/c && "$desktop" >/dev/null 2>&1 &)
      fi
      ;;
  esac
  local i
  for i in $(seq 1 75); do
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  cat >&2 <<'EOF'
Docker is not ready. Start Docker Desktop, then:
  Windows: Settings > Resources > WSL Integration > enable your distro.
  macOS:   start Docker Desktop and wait for "Engine running".
Then run ./sandbox up again.
EOF
  return 1
}

sandbox_verge_dir() {
  if [ -n "${SANDBOX_VERGE_DIR:-}" ]; then
    printf '%s\n' "$SANDBOX_VERGE_DIR"
    return 0
  fi
  local name="io.github.clash-verge-rev.clash-verge-rev"
  local candidates=(
    "$HOME/Library/Application Support/$name"
    "$HOME/.config/$name"
  )
  local candidate
  for candidate in "${candidates[@]}" /mnt/c/Users/*/AppData/Roaming/"$name"; do
    if [ -f "$candidate/profiles.yaml" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

sandbox_node_runner() {
  local verge="$1"
  shift
  docker run --rm -i \
    --user "$(id -u):$(id -g)" \
    --entrypoint python3 \
    -e SANDBOX_STATE_DIR=/sandbox/state \
    -e SANDBOX_VERGE_DIR=/host-verge \
    -v "$SANDBOX_ROOT:/sandbox" \
    -v "$verge:/host-verge:ro" \
    "$SANDBOX_IMAGE" /sandbox/scripts/nodes.py "$@"
}

sandbox_require_nodes() {
  if [ ! -f "$SANDBOX_STATE_DIR/gateway/proxies.yaml" ] || [ ! -s "$SANDBOX_STATE_DIR/gateway/proxies.yaml" ]; then
    cat >&2 <<'EOF'
No proxy nodes are configured. Either:
  1. Select your subscription in Clash Verge Rev and run ./sandbox refresh, or
  2. Import a Clash/mihomo YAML file: ./sandbox import /path/to/config.yaml
EOF
    return 1
  fi
}
