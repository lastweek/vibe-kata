#!/usr/bin/env bash
# Shared helpers for nano-sandbox build/test scripts.

if [ -n "${NK_COMMON_SH_LOADED:-}" ]; then
    return 0
fi
NK_COMMON_SH_LOADED=1

NK_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NK_SCRIPTS_DIR="$NK_PROJECT_DIR/scripts"
NK_TESTDATA_DIR="$NK_PROJECT_DIR/tests"
NK_SUITES_DIR="$NK_SCRIPTS_DIR/suites"
NK_PERF_DIR="$NK_SCRIPTS_DIR/perf"

# Backward-compatible alias for older scripts that still expect NK_TESTS_DIR.
NK_TESTS_DIR="$NK_TESTDATA_DIR"

NS_RUNTIME_BIN="${NS_RUNTIME_BIN:-${NK_RUNTIME_BIN:-/usr/local/bin/ns-runtime}}"
NS_TEST_BUNDLE="${NS_TEST_BUNDLE:-${NK_TEST_BUNDLE:-/usr/local/share/nano-sandbox/bundle}}"
NS_RUN_DIR="${NS_RUN_DIR:-${NK_RUN_DIR:-$HOME/.local/share/nano-sandbox/run}}"

# Backward-compatible aliases for older scripts/env vars.
NK_RUNTIME_BIN="$NS_RUNTIME_BIN"
NK_TEST_BUNDLE="$NS_TEST_BUNDLE"
NK_RUN_DIR="$NS_RUN_DIR"

nk_print_header() {
    local title="$1"
    printf '\n=== %s ===\n' "$title"
}

nk_info() {
    printf '%s\n' "$*"
}

nk_warn() {
    printf 'Warning: %s\n' "$*" >&2
}

nk_die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

nk_usage_error() {
    printf 'Error: %s\n' "$1" >&2
    printf 'Try --help for usage.\n' >&2
    exit 2
}

nk_require_cmd() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        if [ -n "$hint" ]; then
            nk_die "$cmd is required. $hint"
        fi
        nk_die "$cmd is required"
    fi
}

nk_require_linux() {
    if [ "$(uname -s)" != "Linux" ]; then
        nk_die "this script must run on Linux"
    fi
}

nk_require_installed_runtime() {
    [ -x "$NS_RUNTIME_BIN" ] || nk_die "runtime not found at $NS_RUNTIME_BIN. Run: make install"
}

nk_require_installed_bundle() {
    [ -d "$NS_TEST_BUNDLE" ] || nk_die "bundle not found at $NS_TEST_BUNDLE. Run: make install"
    [ -d "$NS_TEST_BUNDLE/rootfs/bin" ] || nk_die "bundle rootfs missing at $NS_TEST_BUNDLE/rootfs/bin. Run: make install"
    nk_check_rootfs_exec_ready "$NS_TEST_BUNDLE/rootfs" || \
        nk_die "bundle rootfs is not executable on this host. Rebuild rootfs and reinstall bundle."
}

nk_prepare_run_dir() {
    mkdir -p "$NS_RUN_DIR"
}

nk_host_elf_pattern() {
    case "$(uname -m)" in
        x86_64|amd64) echo "x86-64" ;;
        aarch64|arm64) echo "ARM aarch64" ;;
        *) echo "" ;;
    esac
}

nk_check_rootfs_exec_ready() {
    local rootfs="$1"
    local busybox="$rootfs/bin/busybox"
    local shbin="$rootfs/bin/sh"

    if [ ! -d "$rootfs" ]; then
        echo "rootfs directory not found: $rootfs" >&2
        return 1
    fi
    if [ ! -x "$busybox" ]; then
        echo "missing executable: $busybox" >&2
        return 1
    fi
    if [ ! -L "$shbin" ] && [ ! -x "$shbin" ]; then
        echo "missing shell entrypoint: $shbin" >&2
        return 1
    fi

    if command -v file >/dev/null 2>&1; then
        local expected_pattern busybox_info interp_path
        expected_pattern="$(nk_host_elf_pattern)"
        busybox_info="$(file "$busybox" 2>/dev/null || true)"

        if [ -n "$expected_pattern" ] && ! printf '%s\n' "$busybox_info" | grep -qi "$expected_pattern"; then
            echo "busybox architecture mismatch for host $(uname -m): $busybox_info" >&2
            return 1
        fi

        interp_path="$(printf '%s\n' "$busybox_info" | sed -n 's/.*interpreter \([^,]*\).*/\1/p')"
        if [ -n "$interp_path" ]; then
            if [ ! -e "$rootfs$interp_path" ]; then
                echo "missing busybox interpreter in rootfs: $interp_path" >&2
                return 1
            fi
            if [ -n "$expected_pattern" ] && ! file "$rootfs$interp_path" | grep -qi "$expected_pattern"; then
                echo "interpreter architecture mismatch for host $(uname -m): $(file "$rootfs$interp_path")" >&2
                return 1
            fi
        fi
    fi

    return 0
}

nk_run_named_script() {
    local script="$1"
    local name="$2"

    printf 'Running: %s\n' "$name"
    printf '================================\n'
    if bash "$script"; then
        printf '✓ %s PASSED\n\n' "$name"
    else
        printf '✗ %s FAILED\n\n' "$name"
        return 1
    fi
}
