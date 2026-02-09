#!/usr/bin/env bash
# Smoke tests: quick validation before integration/perf.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

nk_print_header "nano-sandbox Smoke Tests"

printf '[1/6] Checking installed binary...\n'
nk_require_installed_runtime
printf '✓ Binary exists at %s\n' "$NS_RUNTIME_BIN"

printf '\n[2/6] Checking basic commands...\n'
"$NS_RUNTIME_BIN" -v >/dev/null 2>&1
printf '✓ Version command works\n'
"$NS_RUNTIME_BIN" -h >/dev/null 2>&1
printf '✓ Help command works\n'

printf '\n[3/6] Checking state management...\n'
nk_prepare_run_dir
[ -w "$NS_RUN_DIR" ] || nk_die "state directory is not writable: $NS_RUN_DIR"
printf '✓ State directory is writable (%s)\n' "$NS_RUN_DIR"

printf '\n[4/6] Checking installed bundle...\n'
[ -d "$NS_TEST_BUNDLE" ] || nk_die "bundle missing at $NS_TEST_BUNDLE"
printf '✓ Bundle directory exists at %s\n' "$NS_TEST_BUNDLE"

printf '\n[5/6] Checking OCI config...\n'
[ -f "$NS_TEST_BUNDLE/config.json" ] || nk_die "missing OCI config: $NS_TEST_BUNDLE/config.json"
grep -q '"ociVersion"' "$NS_TEST_BUNDLE/config.json" || nk_die "OCI config missing ociVersion"
printf '✓ OCI config is present and valid\n'

printf '\n[6/6] Checking rootfs...\n'
[ -d "$NS_TEST_BUNDLE/rootfs/bin" ] || nk_die "rootfs missing: $NS_TEST_BUNDLE/rootfs/bin"
BIN_COUNT="$(find "$NS_TEST_BUNDLE/rootfs/bin" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
printf '✓ Root filesystem exists (%s binaries)\n' "$BIN_COUNT"

printf '\n=== Smoke Tests Passed ===\n'
printf 'Ready for integration testing.\n'
