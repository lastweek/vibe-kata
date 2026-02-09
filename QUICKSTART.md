# Quick Start: Running Your First Container

For runtime internals and architecture, see [`docs/README.md`](docs/README.md).

## Step 1: Build and Install nano-sandbox

```bash
# Build and install system-wide (default prefix: /usr/local)
sudo make install

# If this path is on SSHFS/shared mount and sudo can't read files:
make install-system
```

This installs:
- `/usr/local/bin/ns-runtime` - The runtime binary
- `/usr/local/share/nano-sandbox/bundle` - Test bundle with rootfs

## Step 2: Setup Root Filesystem (if needed)

If the test bundle doesn't have a rootfs yet, download Alpine Linux mini rootfs (~5MB):

```bash
./scripts/setup-rootfs.sh
```

This downloads Alpine Linux and sets it up in `tests/bundle/rootfs/`.

## Step 3: Run a Container!

### Using Installed Binary

```bash
# Use the installed binary and bundle
/usr/local/bin/ns-runtime create --bundle=/usr/local/share/nano-sandbox/bundle alpine

# Start existing container (detached by default, like docker start)
/usr/local/bin/ns-runtime start alpine

# Or create+start in one step (attached by default, like docker run)
/usr/local/bin/ns-runtime run --bundle=/usr/local/share/nano-sandbox/bundle alpine-run

# Check state
/usr/local/bin/ns-runtime state alpine

# Delete when done
/usr/local/bin/ns-runtime delete alpine
```

### Using Build Directory Binary

```bash
# Or use the binary from the build directory
./build/bin/ns-runtime create --bundle=./tests/bundle alpine
./build/bin/ns-runtime start alpine
./build/bin/ns-runtime run --bundle=./tests/bundle alpine-run
./build/bin/ns-runtime state alpine
./build/bin/ns-runtime delete alpine

# Run detached create+start
./build/bin/ns-runtime run -d --bundle=./tests/bundle alpine-bg
```

## Step 4: Run Tests

```bash
# Run all tests
./scripts/test.sh

# Or run specific test suites
./scripts/test.sh smoke         # Smoke tests
./scripts/test.sh integration   # Integration tests

# Run benchmarks
./scripts/bench.sh
```

## What You'll See

The container will run with:
- ✅ **PID isolation**: Container can't see host processes
- ✅ **Network isolation**: Separate network stack
- ✅ **Filesystem isolation**: Separate rootfs with `/bin/sh`, `/bin/ls`, etc.
- ✅ **Hostname isolation**: Container has its own hostname
- ✅ **IPC isolation**: Separate IPC mechanisms

## Educational Mode

Want to learn what's happening under the hood? Enable educational mode:

```bash
# Shows explanations for each operation
/usr/local/bin/ns-runtime create --bundle=/usr/local/share/nano-sandbox/bundle -E alpine
/usr/local/bin/ns-runtime start alpine
```

This will explain:
- Why clone() is used instead of fork()
- What each namespace does
- How pivot_root changes the root filesystem
- And more!

## Troubleshooting

**"Runtime binary not found"**
- Run `make install` first

**"Test bundle not found"**
- Run `make install` to install the bundle
- Or run `./scripts/setup-rootfs.sh` to setup rootfs

**"Failed to execute /bin/sh"**
- Rootfs is missing or not executable on this host architecture.
- Repair and reinstall:
  - `./scripts/setup-rootfs.sh --force`
  - `make install`

**"Exec format error" when starting container**
- Rootfs architecture does not match host CPU (for example `x86_64` rootfs on `aarch64` host)
- Rebuild rootfs and reinstall bundle:
  - `./scripts/setup-rootfs.sh --force`
  - `make install`

**Permission denied**
- Need to run as root for some operations (pivot_root, namespaces)

**Build errors**
- Ensure `libjansson-dev` is installed: `sudo apt-get install libjansson-dev`

## Alternative: Use Docker Export

Want a different rootfs? Export from Docker:

```bash
# Export any Docker image
docker export $(docker create alpine:latest) | tar -C tests/bundle/rootfs -xf

# Then reinstall to update the bundle
make install
```

## Clean Up

```bash
# Uninstall nano-sandbox
make uninstall

# Or remove manually
sudo rm -rf /usr/local/bin/ns-runtime
sudo rm -rf /usr/local/share/nano-sandbox
```
