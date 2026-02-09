#!/usr/bin/env bash
# Test runner for nano-sandbox.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: ./scripts/test.sh [all|smoke|integration|perf]

Suites:
  all          Run smoke, integration, and perf
  smoke        Run smoke tests only
  integration  Run integration tests only
  perf         Run perf benchmarks only
USAGE
}

suite="${1:-all}"
case "$suite" in
    -h|--help)
        usage
        exit 0
        ;;
    all|smoke|integration|perf)
        ;;
    *)
        nk_usage_error "unknown suite: $suite"
        ;;
esac

nk_print_header "nano-sandbox Test Runner"
nk_info "Runtime: $NS_RUNTIME_BIN"
nk_info "Bundle:  $NS_TEST_BUNDLE"
nk_info "Suite:   $suite"

nk_require_installed_runtime
nk_require_installed_bundle
nk_prepare_run_dir

run_smoke() {
    nk_run_named_script "$NK_SUITES_DIR/smoke.sh" "Smoke Tests"
}

run_integration() {
    nk_run_named_script "$NK_SUITES_DIR/integration/test_lifecycle.sh" "Integration Tests"
}

run_perf() {
    nk_run_named_script "$NK_SCRIPTS_DIR/bench.sh" "Performance Benchmarks"
}

case "$suite" in
    smoke)
        run_smoke
        ;;
    integration)
        run_integration
        ;;
    perf)
        run_perf
        ;;
    all)
        run_smoke
        run_integration
        run_perf
        ;;
esac

nk_info "=== All Tests Complete ==="
