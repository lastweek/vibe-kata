# Quick Start: Running Your First Container

## Step 1: Build nano-kata

```bash
make
```

## Step 2: Setup Root Filesystem

The test bundle needs a root filesystem. Download Alpine Linux mini rootfs (~5MB):

```bash
./scripts/setup-rootfs.sh
```

This downloads Alpine Linux and sets it up in `tests/bundle/rootfs/`.

## Step 3: Run a Container!

```bash
# Create container
./bin/nk-runtime create --bundle=./tests/bundle alpine

# Start container (runs with full namespace isolation)
./bin/nk-runtime start alpine

# Check state
./bin/nk-runtime state alpine

# Delete when done
./bin/nk-runtime delete alpine
```

## What You'll See

The container will run with:
- ✅ **PID isolation**: Container can't see host processes
- ✅ **Network isolation**: Separate network stack
- ✅ **Filesystem isolation**: Separate rootfs with `/bin/sh`, `/bin/ls`, etc.
- ✅ **Hostname isolation**: Container has its own hostname
- ✅ **IPC isolation**: Separate IPC mechanisms

## Troubleshooting

**"Failed to execute /bin/sh"**
- Rootfs not set up. Run `./scripts/setup-rootfs.sh`

**Permission denied**
- Need to run as root for some operations (pivot_root, namespaces)

**Build errors**
- Ensure `libjansson-dev` is installed: `sudo apt-get install libjansson-dev`

## Alternative: Use Docker Export

Want a different rootfs? Export from Docker:

```bash
# Export any Docker image
docker export $(docker create alpine:latest) | tar -C tests/bundle/rootfs -xf
```
