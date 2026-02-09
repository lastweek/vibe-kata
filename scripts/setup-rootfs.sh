#!/usr/bin/env bash
# Download and install an Alpine mini rootfs into tests/bundle/rootfs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: ./scripts/setup-rootfs.sh [--force]

Options:
  --force     Replace existing tests/bundle/rootfs
  -h, --help  Show this help

Environment:
  ALPINE_VERSION  Alpine version (default: 3.20.3)
  ALPINE_ARCH     Alpine arch (default: auto-detected from host)
USAGE
}

force=false
while [ $# -gt 0 ]; do
    case "$1" in
        --force)
            force=true
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            nk_usage_error "unknown argument: $1"
            ;;
    esac
    shift
done

detect_alpine_arch() {
    local machine
    machine="$(uname -m)"
    case "$machine" in
        x86_64|amd64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        x86|i386|i486|i586|i686)
            echo "x86"
            ;;
        *)
            nk_die "unsupported host architecture '$machine' for auto-detection; set ALPINE_ARCH explicitly"
            ;;
    esac
}

ALPINE_VERSION="${ALPINE_VERSION:-3.20.3}"
ALPINE_ARCH="${ALPINE_ARCH:-$(detect_alpine_arch)}"
ROOTFS_DIR="$NK_PROJECT_DIR/tests/bundle/rootfs"
ALPINE_SERIES="${ALPINE_VERSION%.*}"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_SERIES}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"

nk_require_cmd tar
if command -v curl >/dev/null 2>&1; then
    DOWNLOAD_TOOL="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOAD_TOOL="wget"
else
    nk_die "curl or wget is required to download rootfs"
fi

nk_print_header "Setup Alpine Rootfs"
nk_info "Version: Alpine $ALPINE_VERSION ($ALPINE_ARCH)"
nk_info "Host:    $(uname -m)"
nk_info "Target:  $ROOTFS_DIR"

if [ -d "$ROOTFS_DIR/bin" ] && [ "$force" = false ]; then
    nk_die "rootfs already exists at $ROOTFS_DIR (use --force to replace)"
fi

if [ "$force" = true ]; then
    nk_warn "Replacing existing rootfs at $ROOTFS_DIR"
    rm -rf "$ROOTFS_DIR"
fi

mkdir -p "$ROOTFS_DIR"

tmp_tar="$(mktemp -t nano-sandbox-rootfs.XXXXXX.tar.gz)"
cleanup() {
    rm -f "$tmp_tar"
}
trap cleanup EXIT

nk_info "Downloading rootfs..."
case "$DOWNLOAD_TOOL" in
    curl)
        curl -fsSL -o "$tmp_tar" "$ALPINE_URL"
        ;;
    wget)
        wget -q -O "$tmp_tar" "$ALPINE_URL"
        ;;
esac

nk_info "Extracting rootfs..."
# --no-same-owner/permissions avoids cross-filesystem metadata issues.
tar -xzf "$tmp_tar" -C "$ROOTFS_DIR" --no-same-owner --no-same-permissions

[ -x "$ROOTFS_DIR/bin/busybox" ] || {
    rm -rf "$ROOTFS_DIR"
    nk_die "rootfs extraction failed: $ROOTFS_DIR/bin/busybox missing"
}

# Alpine rootfs commonly uses /bin/sh -> /bin/busybox absolute symlink.
# Validate symlink/path presence without requiring host-side resolution.
[ -L "$ROOTFS_DIR/bin/sh" ] || [ -x "$ROOTFS_DIR/bin/sh" ] || {
    rm -rf "$ROOTFS_DIR"
    nk_die "rootfs extraction failed: $ROOTFS_DIR/bin/sh missing"
}

mkdir -p "$ROOTFS_DIR/proc" "$ROOTFS_DIR/sys" "$ROOTFS_DIR/dev" \
         "$ROOTFS_DIR/pts" "$ROOTFS_DIR/shm" "$ROOTFS_DIR/mqueue" \
         "$ROOTFS_DIR/run" "$ROOTFS_DIR/tmp"

nk_info "Rootfs setup complete"
nk_info "Size:  $(du -sh "$ROOTFS_DIR" | awk '{print $1}')"
nk_info "Files: $(find "$ROOTFS_DIR" | wc -l | tr -d ' ')"
if command -v file >/dev/null 2>&1 && [ -f "$ROOTFS_DIR/bin/busybox" ]; then
    nk_info "Binary: $(file "$ROOTFS_DIR/bin/busybox")"
fi
