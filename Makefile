# nano-sandbox Makefile
# Modernized build/install/test workflow for C systems projects

PROJECT := ns-runtime
VERSION := 0.1.0

# Toolchain (override from environment if needed)
CC ?= cc
PKG_CONFIG ?= pkg-config
INSTALL ?= install
MKDIR_P ?= mkdir -p
RM ?= rm -f

# Build configuration
BUILD_DIR ?= build
BUILD_TYPE ?= debug
SANITIZE ?= none

SRC_DIR := src
INCLUDE_DIR := include
TEST_BUNDLE_DIR := tests/bundle
STAGE_DIR ?= /tmp/nano-sandbox-stage
AUTO_ROOTFS ?= ask

OBJ_DIR := $(BUILD_DIR)/obj
BIN_DIR := $(BUILD_DIR)/bin
TARGET := $(BIN_DIR)/$(PROJECT)

# Installation layout (GNU-style variables)
PREFIX ?= /usr/local
DESTDIR ?=
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
PROJECT_DATADIR ?= $(DATADIR)/nano-sandbox

INSTALL_BIN_DIR := $(DESTDIR)$(BINDIR)
INSTALL_SHARE_DIR := $(DESTDIR)$(PROJECT_DATADIR)
INSTALL_BUNDLE_DIR := $(INSTALL_SHARE_DIR)/bundle

# User-overridable flags
CPPFLAGS ?=
CFLAGS ?=
LDFLAGS ?=
LDLIBS ?=

WARN_FLAGS := -Wall -Wextra -Werror -Wformat=2 -Wstrict-prototypes -Wshadow \
              -Wundef -Wno-format-truncation -Wno-unused-result
BASE_CFLAGS := -std=gnu11 -fstack-protector-strong -fno-omit-frame-pointer -MMD -MP

ifeq ($(BUILD_TYPE),debug)
MODE_CFLAGS := -O0 -g3
MODE_DEFS := -DDEBUG=1
else ifeq ($(BUILD_TYPE),release)
MODE_CFLAGS := -O2 -g -DNDEBUG
MODE_DEFS :=
else
$(error Invalid BUILD_TYPE '$(BUILD_TYPE)'. Use debug or release)
endif

ifeq ($(SANITIZE),none)
SAN_CFLAGS :=
SAN_LDFLAGS :=
else ifeq ($(SANITIZE),address)
SAN_CFLAGS := -fsanitize=address,undefined
SAN_LDFLAGS := -fsanitize=address,undefined
else ifeq ($(SANITIZE),undefined)
SAN_CFLAGS := -fsanitize=undefined
SAN_LDFLAGS := -fsanitize=undefined
else ifeq ($(SANITIZE),thread)
SAN_CFLAGS := -fsanitize=thread
SAN_LDFLAGS := -fsanitize=thread
else
$(error Invalid SANITIZE '$(SANITIZE)'. Use none|address|undefined|thread)
endif

JANSSON_CFLAGS := $(shell $(PKG_CONFIG) --cflags jansson 2>/dev/null)
JANSSON_LIBS := $(shell $(PKG_CONFIG) --libs jansson 2>/dev/null)
ifeq ($(strip $(JANSSON_LIBS)),)
JANSSON_LIBS := -ljansson
endif

HAVE_CAPNG := $(shell $(PKG_CONFIG) --exists libcap-ng && echo 1 || echo 0)
ifeq ($(HAVE_CAPNG),1)
CAPNG_CFLAGS := $(shell $(PKG_CONFIG) --cflags libcap-ng)
CAPNG_LIBS := $(shell $(PKG_CONFIG) --libs libcap-ng)
CAPNG_DEFS := -DHAVE_LIBCAPNG
else
CAPNG_CFLAGS :=
CAPNG_LIBS :=
CAPNG_DEFS :=
endif

CPPFLAGS += -I$(INCLUDE_DIR) $(JANSSON_CFLAGS) $(CAPNG_CFLAGS) $(MODE_DEFS) $(CAPNG_DEFS)
CFLAGS += $(WARN_FLAGS) $(BASE_CFLAGS) $(MODE_CFLAGS) $(SAN_CFLAGS)
LDFLAGS += $(SAN_LDFLAGS)
LDLIBS += -lpthread $(JANSSON_LIBS) $(CAPNG_LIBS)

SRC_FILES := $(sort $(shell find $(SRC_DIR) -type f -name '*.c'))
OBJ_FILES := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRC_FILES))
DEP_FILES := $(OBJ_FILES:.o=.d)

.DEFAULT_GOAL := all

all: $(TARGET)

$(TARGET): $(OBJ_FILES) | $(BIN_DIR)
	@echo "Linking $@"
	$(CC) $(OBJ_FILES) $(LDFLAGS) -o $@ $(LDLIBS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@echo "Compiling $<"
	@$(MKDIR_P) $(@D)
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

$(BIN_DIR):
	@$(MKDIR_P) $@

install: all install-runtime ensure-rootfs install-bundle
	@echo ""
	@echo "Installation complete!"
	@echo "  Binary: $(BINDIR)/$(PROJECT)"
	@echo "  Bundle: $(PROJECT_DATADIR)/bundle"

install-system: all
	@stage="$(STAGE_DIR)"; \
	echo "Staging install under $$stage"; \
	rm -rf "$$stage"; \
	$(MKDIR_P) "$$stage"; \
	$(MAKE) --no-print-directory install DESTDIR="$$stage" PREFIX="$(PREFIX)"; \
	echo "Installing staged files to $(PREFIX) (sudo required)"; \
	sudo $(MKDIR_P) "$(PREFIX)"; \
	sudo cp -a "$$stage$(PREFIX)/." "$(PREFIX)/"; \
	rm -rf "$$stage"; \
	echo "System install complete at $(PREFIX)"

install-runtime:
	@echo "Installing $(PROJECT) to $(INSTALL_BIN_DIR)"
	@$(MKDIR_P) $(INSTALL_BIN_DIR)
	@$(INSTALL) -m 0755 $(TARGET) $(INSTALL_BIN_DIR)/$(PROJECT)

ensure-rootfs:
	@set -eu; \
	rootfs="$(TEST_BUNDLE_DIR)/rootfs"; \
	busybox="$$rootfs/bin/busybox"; \
	shbin="$$rootfs/bin/sh"; \
	need_rootfs=0; \
	reason=""; \
	if [ ! -x "$$busybox" ]; then \
		need_rootfs=1; \
		reason="missing $$busybox"; \
	elif [ ! -L "$$shbin" ] && [ ! -x "$$shbin" ]; then \
		need_rootfs=1; \
		reason="missing $$shbin"; \
	fi; \
	if [ "$$need_rootfs" -eq 0 ] && command -v file >/dev/null 2>&1; then \
		host_arch="$$(uname -m)"; \
		expected_pattern=""; \
		busybox_file="$$(file "$$busybox" 2>/dev/null || true)"; \
		case "$$host_arch" in \
			x86_64|amd64) expected_pattern="x86-64" ;; \
			aarch64|arm64) expected_pattern="ARM aarch64" ;; \
		esac; \
		if [ -n "$$expected_pattern" ] && ! printf '%s\n' "$$busybox_file" | grep -qi "$$expected_pattern"; then \
			need_rootfs=1; \
			reason="rootfs busybox arch mismatch for $$host_arch"; \
		fi; \
		if [ "$$need_rootfs" -eq 0 ]; then \
			interp_path="$$(printf '%s\n' "$$busybox_file" | sed -n 's/.*interpreter \([^,]*\).*/\1/p')"; \
			if [ -n "$$interp_path" ] && [ ! -e "$$rootfs$$interp_path" ]; then \
				need_rootfs=1; \
				reason="rootfs missing ELF interpreter $$interp_path for $$busybox"; \
			elif [ -n "$$interp_path" ] && [ -n "$$expected_pattern" ] && ! file "$$rootfs$$interp_path" | grep -qi "$$expected_pattern"; then \
				need_rootfs=1; \
				reason="rootfs interpreter arch mismatch for $$host_arch ($$interp_path)"; \
			fi; \
		fi; \
	fi; \
	if [ "$$need_rootfs" -eq 0 ]; then \
		echo "Rootfs preflight: OK ($$busybox)"; \
		exit 0; \
	fi; \
	echo "Rootfs preflight: $$reason"; \
	do_download=0; \
	case "$(AUTO_ROOTFS)" in \
		1|yes|true|TRUE|YES) \
			do_download=1 ;; \
		0|no|false|FALSE|NO) \
			do_download=0 ;; \
		*) \
			if [ -t 0 ]; then \
				printf "Rootfs is missing/incompatible. Download now via ./scripts/setup-rootfs.sh --force ? [y/N] "; \
				read -r answer; \
				case "$$answer" in \
					y|Y|yes|YES) do_download=1 ;; \
				esac; \
			fi ;; \
	esac; \
	if [ "$$do_download" -eq 0 ]; then \
		echo "Error: rootfs required for install-bundle"; \
		echo "Hint: run ./scripts/setup-rootfs.sh --force"; \
		echo "Hint: or run make install AUTO_ROOTFS=1"; \
		exit 1; \
	fi; \
	echo "Downloading rootfs (requested by install flow)..."; \
	./scripts/setup-rootfs.sh --force; \
	if [ ! -x "$$busybox" ]; then \
		echo "Error: rootfs setup did not produce $$busybox"; \
		exit 1; \
	fi; \
	if command -v file >/dev/null 2>&1; then \
		busybox_file="$$(file "$$busybox" 2>/dev/null || true)"; \
		interp_path="$$(printf '%s\n' "$$busybox_file" | sed -n 's/.*interpreter \([^,]*\).*/\1/p')"; \
		if [ -n "$$interp_path" ] && [ ! -e "$$rootfs$$interp_path" ]; then \
			echo "Error: rootfs setup produced busybox with missing interpreter $$interp_path"; \
			exit 1; \
		fi; \
	fi; \
	echo "Rootfs preflight: ready ($$busybox)"

install-bundle:
	@if [ -d "$(TEST_BUNDLE_DIR)" ]; then \
		echo "Installing test bundle to $(INSTALL_BUNDLE_DIR)"; \
		rm -rf "$(INSTALL_BUNDLE_DIR)"; \
		$(MKDIR_P) "$(INSTALL_BUNDLE_DIR)"; \
		(cd "$(TEST_BUNDLE_DIR)" && tar -cf - .) | (cd "$(INSTALL_BUNDLE_DIR)" && tar -xf -); \
		chmod -R a+rX "$(INSTALL_BUNDLE_DIR)"; \
	else \
		echo "Warning: $(TEST_BUNDLE_DIR) not found. Run: ./scripts/setup-rootfs.sh"; \
	fi

uninstall:
	@echo "Removing $(PROJECT) from $(DESTDIR)$(PREFIX)"
	@$(RM) "$(INSTALL_BIN_DIR)/$(PROJECT)"
	@rm -rf "$(INSTALL_BUNDLE_DIR)"

clean:
	@echo "Cleaning build artifacts"
	@rm -rf "$(BUILD_DIR)" obj bin

distclean: clean
	@echo "Cleaning runtime/test artifacts"
	@rm -rf run build.log

check-deps:
	@echo "Checking build dependencies..."
	@command -v $(CC) >/dev/null || { echo "Error: $(CC) not found"; exit 1; }
	@command -v $(PKG_CONFIG) >/dev/null || { echo "Error: $(PKG_CONFIG) not found"; exit 1; }
	@$(PKG_CONFIG) --exists jansson || { \
		echo "Error: jansson development files not found"; \
		echo "Ubuntu/Debian: sudo apt-get install libjansson-dev"; \
		echo "macOS: brew install jansson"; \
		exit 1; \
	}
	@echo "Dependencies OK"

debug:
	$(MAKE) BUILD_TYPE=debug SANITIZE=none all

release:
	$(MAKE) BUILD_TYPE=release SANITIZE=none all

asan:
	$(MAKE) BUILD_TYPE=debug SANITIZE=address all

ubsan:
	$(MAKE) BUILD_TYPE=debug SANITIZE=undefined all

tsan:
	$(MAKE) BUILD_TYPE=debug SANITIZE=thread all

test: install
	./scripts/test.sh all

test-smoke: install
	./scripts/test.sh smoke

test-integration: install
	./scripts/test.sh integration

test-perf: install
	./scripts/test.sh perf

bench:
	./scripts/bench.sh

vm-test:
	./scripts/vm-sync-test.sh integration

ecs-test:
	./scripts/ecs-sync-test.sh $(if $(ECS_SUITE),$(ECS_SUITE),integration)

print-config:
	@echo "PROJECT=$(PROJECT)"
	@echo "VERSION=$(VERSION)"
	@echo "CC=$(CC)"
	@echo "BUILD_TYPE=$(BUILD_TYPE)"
	@echo "SANITIZE=$(SANITIZE)"
	@echo "BUILD_DIR=$(BUILD_DIR)"
	@echo "TARGET=$(TARGET)"
	@echo "PREFIX=$(PREFIX)"
	@echo "DESTDIR=$(DESTDIR)"
	@echo "HAVE_CAPNG=$(HAVE_CAPNG)"

help:
	@echo "nano-sandbox Build System"
	@echo ""
	@echo "Primary targets:"
	@echo "  all              Build runtime (default)"
	@echo "  install          Install runtime + test bundle"
	@echo "  install-system   Stage to /tmp then sudo-copy to PREFIX (SSHFS-safe)"
	@echo "  uninstall        Remove installed runtime + bundle"
	@echo "  clean            Remove build artifacts"
	@echo "  distclean        Remove build + runtime artifacts"
	@echo "  check-deps       Validate toolchain dependencies"
	@echo ""
	@echo "Build profiles:"
	@echo "  debug            Build with debug flags"
	@echo "  release          Build with release flags"
	@echo "  asan             Debug build with AddressSanitizer"
	@echo "  ubsan            Debug build with UndefinedBehaviorSanitizer"
	@echo "  tsan             Debug build with ThreadSanitizer"
	@echo ""
	@echo "Test targets:"
	@echo "  test             Install + run all tests"
	@echo "  test-smoke       Install + run smoke tests"
	@echo "  test-integration Install + run integration tests"
	@echo "  test-perf        Install + run perf benchmarks"
	@echo "  bench            Run benchmarks"
	@echo "  vm-test          Run integration tests in Ubuntu VM"
	@echo "  ecs-test         Sync/build/test on ECS server"
	@echo ""
	@echo "Config vars (override via environment or CLI):"
	@echo "  BUILD_TYPE=debug|release"
	@echo "  SANITIZE=none|address|undefined|thread"
	@echo "  BUILD_DIR=<path>"
	@echo "  PREFIX=<install prefix>"
	@echo "  DESTDIR=<staging root>"
	@echo "  STAGE_DIR=<temp staging dir for install-system>"
	@echo "  AUTO_ROOTFS=ask|1|0   Download rootfs during install (ask=default)"
	@echo "  ECS_SUITE=smoke|integration|perf|all"
	@echo ""
	@echo "Examples:"
	@echo "  make release"
	@echo "  make asan"
	@echo "  make BUILD_TYPE=release install PREFIX=/usr/local"
	@echo "  make install DESTDIR=/tmp/pkgroot PREFIX=/usr"

.PHONY: all install install-system install-runtime ensure-rootfs install-bundle uninstall clean distclean \
	check-deps debug release asan ubsan tsan test test-smoke test-integration \
	test-perf bench vm-test ecs-test print-config help

-include $(DEP_FILES)
