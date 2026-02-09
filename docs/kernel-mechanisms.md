# Kernel Mechanisms

## Process Creation Model

- Primitive: `clone()` (not plain `fork()`)
- Reason: namespace selection must be applied at process creation boundary.
- Clone flags are derived from OCI namespace list.

## Namespaces

Supported mapping from OCI -> runtime:
- `pid` -> `CLONE_NEWPID`
- `network` -> `CLONE_NEWNET`
- `ipc` -> `CLONE_NEWIPC`
- `uts` -> `CLONE_NEWUTS`
- `mount` -> `CLONE_NEWNS`
- `user` / `cgroup` are parsed and represented for evolving support

Effects:
- Isolated process tree view
- Isolated hostname/network/IPC scopes
- Isolated mount namespace for rootfs operations

## Filesystem Isolation

Core path: `src/container/mounts.c`

Key steps:
1. Prepare container rootfs path from bundle.
2. Configure mount propagation/private behavior.
3. Enter the rootfs context for child execution.
4. Ensure expected pseudo-filesystem mount points exist (e.g. proc/sys/dev paths).

Why ENOENT can happen even when `/bin/sh` exists:
- ELF interpreter referenced by `/bin/sh` target is missing or wrong architecture.
- Example: busybox expects `/lib/ld-musl-x86_64.so.1`, but rootfs only has aarch64 loader.

## Cgroups

Core path: `src/container/cgroups.c`

Behavior:
- Runtime creates/uses cgroup subtree for container id.
- Child PID is added to cgroup after process creation.
- Delete flow removes container cgroup path.

## Capability / Limits Handling

Core path: `src/container/process.c`

- Capability drop path uses `libcap-ng` when available.
- If unavailable, runtime logs warning and continues (educational fallback).
- Resource limits (e.g. stack) are configured before `execve`.

## Parent/Child Synchronization

- Parent and child communicate via pipe.
- Child emits readiness only after rootfs/setup stage completes.
- Parent treats readiness failure as startup failure and avoids false running state.

## Signals and Lifecycle

- Delete path attempts graceful termination (`SIGTERM`) before forced kill (`SIGKILL`).
- Attached `start`/`run` waits and reports exit code semantics.

## Security and Production Notes

This project is educational and intentionally minimal. For production hardening, typical additions include:
- Full user namespace/idmap model
- Seccomp profile enforcement
- LSM integration (SELinux/AppArmor)
- Device cgroup and mount whitelisting policy
- Stronger lifecycle supervision semantics
