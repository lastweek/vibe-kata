# Build and Test Pipeline

## Build Targets

Primary Make targets:
- `make` / `make all`: compile runtime into `build/bin/ns-runtime`
- `make install`: install binary + validated bundle
- `make install-system`: SSHFS-safe staged install + sudo copy
- `make check-deps`: verify toolchain/deps
- `make clean` / `make distclean`

## Install Preflight (Rootfs Safety)

`make install` runs `ensure-rootfs` before bundle install.

Validation includes:
1. `rootfs/bin/busybox` exists and executable
2. `rootfs/bin/sh` exists (symlink or executable)
3. busybox architecture matches host
4. busybox ELF interpreter exists in rootfs and matches host architecture

Behavior controls:
- `AUTO_ROOTFS=ask` (default): prompt interactively
- `AUTO_ROOTFS=1`: auto-download rootfs
- `AUTO_ROOTFS=0`: fail with remediation hints

## Test Suite Structure

Entry point: `scripts/test.sh`

Suites:
- `smoke`: fast install/runtime sanity checks + rootfs executable checks
- `integration`: lifecycle semantics + state transitions + run path coverage
- `perf`: benchmark scripts

### Integration Guarantees

Integration suite validates:
- `create/start/delete` lifecycle
- `run --rm` lifecycle and cleanup behavior
- failures if runtime logs child startup/exec errors
- non-existent container error handling

It uses `sudo -n` for runtime operations after credential precheck.

## VM Workflow (macOS + Ubuntu VM)

Script: `scripts/vm-sync-test.sh`

High-level flow:
1. `rsync` source into native VM path
2. run `sudo make install` in VM
3. run selected test suite in VM

Default endpoint:
- `ys@127.0.0.1:2222`

## ECS Workflow

Script: `scripts/ecs-sync-test.sh`

High-level flow:
1. `rsync` to ECS host
2. optional dependency bootstrap
3. rootfs compatibility preflight on remote
4. `make install` + selected tests

Default endpoint:
- `root@118.196.47.98`

## Known Environment Pitfalls

- PTY issues on remote hosts can break interactive sudo/ssh flows.
- Minimal hosts may lack `git`, `rg`, or DNS access for rootfs download.
- Shared mounts (SSHFS) can break `sudo make install`; use `make install-system`.

## Recommended Release Gate

Before pushing release tags:
1. `make check-deps`
2. `make install AUTO_ROOTFS=0`
3. `./scripts/test.sh smoke`
4. `./scripts/test.sh integration`
5. VM/ECS remote suite run for the target deployment path
