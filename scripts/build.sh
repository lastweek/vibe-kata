#!/usr/bin/env bash
# Build helper for nano-sandbox.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<USAGE
Usage: ./scripts/build.sh [--install] [--clean] [--mode debug|release] [--sanitize NAME] [-j N]

Options:
  --install   Run 'make install' after build
  --clean     Run 'make clean' before build
  --mode      Build type: debug|release (default: debug)
  --sanitize  Sanitizer: none|address|undefined|thread (default: none)
  -j, --jobs  Parallel build jobs (passed to make -j)
  -h, --help  Show this help
USAGE
}

do_install=false
clean_first=false
build_mode="${BUILD_TYPE:-debug}"
sanitize="${SANITIZE:-none}"
jobs=""
install_prefix="${PREFIX:-/usr/local}"

while [ $# -gt 0 ]; do
    case "$1" in
        --install|install)
            do_install=true
            ;;
        --clean|clean)
            clean_first=true
            ;;
        --mode)
            [ $# -ge 2 ] || nk_usage_error "--mode requires an argument"
            build_mode="$2"
            shift
            ;;
        --sanitize)
            [ $# -ge 2 ] || nk_usage_error "--sanitize requires an argument"
            sanitize="$2"
            shift
            ;;
        -j|--jobs)
            [ $# -ge 2 ] || nk_usage_error "$1 requires an argument"
            jobs="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            nk_usage_error "unknown argument: $1"
            ;;
    esac
    shift
done

case "$build_mode" in
    debug|release) ;;
    *) nk_usage_error "invalid mode: $build_mode (expected debug|release)" ;;
esac

case "$sanitize" in
    none|address|undefined|thread) ;;
    *) nk_usage_error "invalid sanitizer: $sanitize (expected none|address|undefined|thread)" ;;
esac

make_args=("BUILD_TYPE=$build_mode" "SANITIZE=$sanitize")
if [ -n "$jobs" ]; then
    make_args+=("-j" "$jobs")
fi

cd "$NK_PROJECT_DIR"

nk_print_header "nano-sandbox Build"
nk_info "Project: $NK_PROJECT_DIR"
nk_info "Mode:    $build_mode"
nk_info "San:     $sanitize"

nk_require_cmd make "Install build tools first"
nk_require_cmd gcc "Install gcc (e.g., sudo apt-get install build-essential)"
nk_require_cmd pkg-config "Install pkg-config"
if ! pkg-config --exists jansson 2>/dev/null; then
    nk_die "libjansson not found. Install: sudo apt-get install libjansson-dev"
fi

if [ "$clean_first" = true ]; then
    nk_info "Cleaning previous artifacts..."
    make clean
fi

nk_info "Building..."
make "${make_args[@]}" all

if [ "$do_install" = true ]; then
    if [ "$(id -u)" -ne 0 ] && [ ! -w "$install_prefix" ]; then
        nk_require_cmd sudo "Install sudo or run as root"
        nk_info "Installing to $install_prefix (using sudo)..."
        sudo make "${make_args[@]}" install
    else
        nk_info "Installing to $install_prefix..."
        make "${make_args[@]}" install
    fi
fi

nk_info "Build complete"
nk_info "Binary: $NK_PROJECT_DIR/build/bin/ns-runtime"

if [ "$do_install" = false ]; then
    nk_info "Next: make install && ./scripts/test.sh"
fi
