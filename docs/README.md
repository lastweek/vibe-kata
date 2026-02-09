# Documentation

This folder contains deep-dive technical documentation for `nano-sandbox`.

## Reading Order

1. [Architecture Overview](architecture.md)
2. [Execution Flow](execution-flow.md)
3. [Kernel Mechanisms](kernel-mechanisms.md)
4. [Build and Test Pipeline](build-and-test.md)

## Scope

These docs describe:
- High-level component boundaries
- Exact command execution paths (`create`, `start`, `run`, `delete`, `state`)
- Linux primitives used under the hood (namespaces, mounts, cgroups, process model)
- Local/VM/ECS build-test workflows and reliability checks
- Mermaid diagrams that render directly in GitHub

## Source of Truth

Behavioral truth is always the code in:
- `src/main.c`
- `src/container/*.c`
- `src/common/state.c`
- `scripts/*.sh`
- `Makefile`

Use this folder as the architectural map, and source files as implementation details.
