#!/bin/bash
# Setup test rootfs for nano-kata
# Downloads Alpine Linux mini rootfs (lightweight, practical)

set -e

ALPINE_VERSION="3.20.3"
ALPINE_ARCH="x86_64"
ROOTFS_DIR="tests/bundle/rootfs"

echo "=== Setting up Alpine rootfs for nano-kata ==="
echo "Version: Alpine $ALPINE_VERSION ($ALPINE_ARCH)"
echo "Target: $ROOTFS_DIR"
echo

# Check if rootfs already exists
if [ -d "$ROOTFS_DIR/bin" ]; then
    echo "Rootfs already exists at $ROOTFS_DIR"
    echo "Remove it first with: rm -rf $ROOTFS_DIR"
    exit 1
fi

# Create directory structure
mkdir -p "$ROOTFS_DIR"

# Download Alpine mini rootfs
echo "Downloading Alpine mini rootfs..."
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"

if command -v wget &> /dev/null; then
    wget -q -O /tmp/alpine-rootfs.tar.gz "$ALPINE_URL"
elif command -v curl &> /dev/null; then
    curl -sSL -o /tmp/alpine-rootfs.tar.gz "$ALPINE_URL"
else
    echo "Error: Need wget or curl to download rootfs"
    exit 1
fi

# Extract rootfs
echo "Extracting rootfs..."
tar -xzf /tmp/alpine-rootfs.tar.gz -C "$ROOTFS_DIR"
rm /tmp/alpine-rootfs.tar.gz

# Verify extraction
if [ ! -f "$ROOTFS_DIR/bin/sh" ]; then
    echo "Error: Rootfs extraction failed"
    rm -rf "$ROOTFS_DIR"
    exit 1
fi

# Create essential directories (might not exist in mini rootfs)
mkdir -p "$ROOTFS_DIR"/{proc,sys,dev,pts,shm,mqueue,run,tmp}

# Create minimal inittab for Alpine
cat > "$ROOTFS_DIR/etc/inittab" << 'EOF'
::sysinit:/sbin/openrc sysinit
::shutdown:/sbin/openrc shutdown
::respawn:/sbin/getty 38400 tty1
EOF

echo
echo "=== Rootfs setup complete! ==="
echo "Location: $ROOTFS_DIR"
echo "Size: $(du -sh $ROOTFS_DIR | cut -f1)"
echo "Files: $(find $ROOTFS_DIR | wc -l) files"
echo
echo "Available commands:"
ls "$ROOTFS_DIR/bin" | head -20
echo
echo "Test container:"
echo "  ./bin/nk-runtime create --bundle=./tests/bundle alpine"
echo "  ./bin/nk-runtime start alpine"
