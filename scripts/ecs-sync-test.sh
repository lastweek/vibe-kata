#!/usr/bin/env bash
# Sync this repo to an ECS host and run build+tests remotely.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<USAGE
Usage: ./scripts/ecs-sync-test.sh [smoke|integration|perf|all] [--bootstrap]

Defaults:
  suite=integration
  ECS_USER=root
  ECS_HOST=118.196.47.98
  ECS_PORT=22
  ECS_KEY=~/.ssh/id_rsa
  ECS_REMOTE_DIR=/root/vibe-sandbox

Options:
  --bootstrap   Install build dependencies on remote host (Ubuntu/Debian)
USAGE
}

suite="integration"
bootstrap=false

while [ $# -gt 0 ]; do
    case "$1" in
        smoke|integration|perf|all)
            suite="$1"
            ;;
        --bootstrap)
            bootstrap=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            usage
            exit 2
            ;;
    esac
    shift
done

: "${ECS_USER:=root}"
: "${ECS_HOST:=118.196.47.98}"
: "${ECS_PORT:=22}"
: "${ECS_KEY:=$HOME/.ssh/id_rsa}"
: "${ECS_REMOTE_DIR:=/root/vibe-sandbox}"

SSH_OPTS=(-i "$ECS_KEY" -p "$ECS_PORT" -o StrictHostKeyChecking=accept-new)
REMOTE="${ECS_USER}@${ECS_HOST}"

echo "==> Syncing source to ECS"
echo "    local : $PROJECT_DIR"
echo "    remote: ${REMOTE}:${ECS_REMOTE_DIR}"
rsync -az --delete \
    --exclude '.git' \
    --exclude '.claude' \
    --exclude 'build' \
    --exclude 'obj' \
    --exclude 'bin' \
    --exclude 'run' \
    --exclude '*.log' \
    -e "ssh ${SSH_OPTS[*]}" \
    "$PROJECT_DIR/" \
    "${REMOTE}:${ECS_REMOTE_DIR}/"

if [ "$bootstrap" = true ]; then
    echo "==> Installing remote dependencies"
    ssh "${SSH_OPTS[@]}" "$REMOTE" \
        "export DEBIAN_FRONTEND=noninteractive; apt-get update -y && apt-get install -y build-essential pkg-config libjansson-dev"
fi

echo "==> Running remote build + tests ($suite)"
ssh "${SSH_OPTS[@]}" "$REMOTE" "bash -s -- '$ECS_REMOTE_DIR' '$suite'" <<'EOF'
set -euo pipefail
remote_dir="$1"
suite="$2"
cd "$remote_dir"

host_arch="$(uname -m)"
expected_pattern=""
case "$host_arch" in
    x86_64|amd64) expected_pattern="x86-64" ;;
    aarch64|arm64) expected_pattern="ARM aarch64" ;;
esac

needs_rootfs=false
busybox_path="tests/bundle/rootfs/bin/busybox"
if [ ! -x "$busybox_path" ]; then
    needs_rootfs=true
elif command -v file >/dev/null 2>&1; then
    busybox_info="$(file "$busybox_path" 2>/dev/null || true)"
    if [ -n "$expected_pattern" ] && ! printf '%s\n' "$busybox_info" | grep -qi "$expected_pattern"; then
        needs_rootfs=true
    else
        interp_path="$(printf '%s\n' "$busybox_info" | sed -n 's/.*interpreter \([^,]*\).*/\1/p')"
        if [ -n "$interp_path" ] && [ ! -e "tests/bundle/rootfs${interp_path}" ]; then
            needs_rootfs=true
        elif [ -n "$interp_path" ] && [ -n "$expected_pattern" ] && ! file "tests/bundle/rootfs${interp_path}" | grep -qi "$expected_pattern"; then
            needs_rootfs=true
        fi
    fi
fi

if [ "$needs_rootfs" = true ]; then
    ./scripts/setup-rootfs.sh --force
fi

make install
./scripts/test.sh "$suite"
EOF
