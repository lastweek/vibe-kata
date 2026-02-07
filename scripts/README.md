# Scripts Directory

This directory contains helper scripts for nano-kata development and testing.

## setup-rootfs.sh

Downloads and sets up an Alpine Linux mini rootfs for testing containers.

**Usage:**
```bash
./scripts/setup-rootfs.sh
```

**What it does:**
- Downloads Alpine mini rootfs (~5MB)
- Extracts to `tests/bundle/rootfs/`
- Creates essential device directories
- Sets up minimal inittab

**Why Alpine?**
- Tiny: Only ~5MB uncompressed
- Practical: Real Linux distribution used in production
- Complete: Includes package manager (`apk`) for adding tools
- Educational: Industry standard for minimal containers

**After running this:**
```bash
./bin/nk-runtime create --bundle=./tests/bundle alpine
./bin/nk-runtime start alpine
```

**Clean up:**
```bash
rm -rf tests/bundle/rootfs
```

## Other Scripts (Development)

- `build-and-test.sh` - Build and run tests (requires Linux)
- `build-simple.exp` - Build via SSH to Linux environment
- `test-*.exp` - Various test scripts
