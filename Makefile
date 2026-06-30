# Makefile
# capp-build
#
# Created by David Richardson on 2026-04-28.
#
# Development workflow:
#   make build        Build a native binary to build/
#   make run          Build and run immediately
#
# Release workflow:
#   1. Update VERSION.txt and CHANGELOG.md.
#   2. Commit and push.
#   3. make release
#   Requires: gh (GitHub CLI), authenticated with repo write access.
#
# Cross-compilation:
#   capp-build has a CGo dependency via capp-parse (go-tree-sitter).
#   All six platform targets are produced using Zig as the C cross-compiler.
#   Darwin targets require a macOS host; the macOS SDK is resolved via xcrun.
#
#   Linux targets pin glibc 2.28 for broad distribution compatibility.
#   Windows targets produce .exe binaries via the Zig mingw-w64 toolchain.
#
# Version embedding:
#   Lisette has no mutable package-level vars, so ldflags injection is not
#   viable. VERSION is written into src/version_generated.lis before each
#   build and reset to "dev" afterwards.
#
#   VERSION.txt is the single source of truth for the project version.
#   lisette.toml's [project] version field is a derived artifact, rewritten
#   from VERSION.txt by `sync-version` before every build. Do not edit it
#   by hand — changes will be overwritten on the next build.

BINARY       := capp-build
BUILD_DIR    := build
TARGET       := target
VERSION      := $(shell head -1 VERSION.txt)
COMMIT       := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
VERSION_FILE := src/version_generated.lis
MACOS_SDK    := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null)

.PHONY: all build run build-all checksums release clean sync-version

all: build

# ---------------------------------------------------------------------------
# Version sync — lisette.toml is derived from VERSION.txt
# ---------------------------------------------------------------------------

sync-version:
	@sed -i.bak 's/^version = ".*"/version = "$(VERSION)"/' lisette.toml && rm -f lisette.toml.bak

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

build: sync-version
	lis format
	@printf '//**\n// version_generated.lis\n// capp-build\n//\n// Generated — do not edit by hand.\n// **\n\npub const VERSION: string = "$(VERSION) ($(COMMIT))"\n' \
		> "$(VERSION_FILE)"
	cd "$(TARGET)" && go mod tidy
	lis build

run: build
	"$(TARGET)/bin/$(BINARY)"

clean:
	rm -rf "$(BUILD_DIR)"
	rm -rf $(TARGET)/vendor
	rm -f $(TARGET)/go.sum

# ---------------------------------------------------------------------------
# Release builds — all six platform targets via Zig CC
# ---------------------------------------------------------------------------

build-all: sync-version
	lis format
	@printf '//**\n// version_generated.lis\n// capp-build\n//\n// Generated — do not edit by hand.\n// **\n\npub const VERSION: string = "$(VERSION) ($(COMMIT))"\n' \
		> "$(VERSION_FILE)"
	lis emit
	cd "$(TARGET)" && go mod tidy
	@mkdir -p "$(BUILD_DIR)"
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	echo "building darwin/arm64 ..."; \
	CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
		CC="zig cc -target aarch64-macos -isysroot $(MACOS_SDK) -L$(MACOS_SDK)/usr/lib -F$(MACOS_SDK)/System/Library/Frameworks" \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_darwin_arm64_$(VERSION)" . || exit 1; \
	echo "building darwin/amd64 ..."; \
	CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
		CC="zig cc -target x86_64-macos -isysroot $(MACOS_SDK) -L$(MACOS_SDK)/usr/lib -F$(MACOS_SDK)/System/Library/Frameworks" \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_darwin_amd64_$(VERSION)" . || exit 1; \
	echo "building linux/arm64 ..."; \
	printf '#!/bin/sh\nexec zig cc -target aarch64-linux-gnu.2.28 "$$@"\n' > "$$tmp/zcc-linux-arm64"; \
	chmod +x "$$tmp/zcc-linux-arm64"; \
	CC="$$tmp/zcc-linux-arm64" CGO_ENABLED=1 GOOS=linux GOARCH=arm64 \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_linux_arm64_$(VERSION)" . || exit 1; \
	echo "building linux/amd64 ..."; \
	printf '#!/bin/sh\nexec zig cc -target x86_64-linux-gnu.2.28 "$$@"\n' > "$$tmp/zcc-linux-amd64"; \
	chmod +x "$$tmp/zcc-linux-amd64"; \
	CC="$$tmp/zcc-linux-amd64" CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_linux_amd64_$(VERSION)" . || exit 1; \
	echo "building windows/arm64 ..."; \
	printf '#!/bin/sh\nexec zig cc -target aarch64-windows "$$@"\n' > "$$tmp/zcc-windows-arm64"; \
	chmod +x "$$tmp/zcc-windows-arm64"; \
	CC="$$tmp/zcc-windows-arm64" CGO_ENABLED=1 GOOS=windows GOARCH=arm64 \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_windows_arm64_$(VERSION).exe" . || exit 1; \
	echo "building windows/amd64 ..."; \
	printf '#!/bin/sh\nexec zig cc -target x86_64-windows "$$@"\n' > "$$tmp/zcc-windows-amd64"; \
	chmod +x "$$tmp/zcc-windows-amd64"; \
	CC="$$tmp/zcc-windows-amd64" CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
		go build -C "$(TARGET)" -o "../$(BUILD_DIR)/$(BINARY)_windows_amd64_$(VERSION).exe" . || exit 1; \
	echo "all platforms built."
	@printf '//**\n// version_generated.lis\n// capp-build\n//\n// Generated — do not edit by hand.\n// **\n\npub const VERSION: string = "dev"\n' \
		> "$(VERSION_FILE)"

checksums:
	@echo "computing checksums ..."
	@cd "$(BUILD_DIR)" && for f in $(BINARY)_*; do \
		[ -f "$$f" ] && shasum -a 256 "$$f" | awk '{print $$1}' > "$$f.sha256" \
		&& echo "  $$f.sha256"; \
	done || true
	@echo "done."

# ---------------------------------------------------------------------------
# Release — requires gh authenticated with repo write access
# ---------------------------------------------------------------------------

release: build-all checksums
	@if ! gh auth status > /dev/null 2>&1; then \
		echo "error: gh is not authenticated — run 'gh auth login' first" >&2; exit 1; \
	fi
	@tag="v$(VERSION)"; \
	notes=$$(awk "/^## $(VERSION)/{found=1; next} found && /^## /{exit} found{print}" CHANGELOG.md); \
	[ -z "$$notes" ] && notes="Release $(VERSION)"; \
	prerelease=""; \
	case "$(VERSION)" in *-*) prerelease="--prerelease" ;; esac; \
	echo "creating release $$tag ..."; \
	gh release create "$$tag" \
		--title "$$tag" \
		--notes "$$notes" \
		$$prerelease; \
	echo "uploading artifacts ..."; \
	for f in "$(BUILD_DIR)"/$(BINARY)_* "$(BUILD_DIR)"/*.sha256; do \
		[ -f "$$f" ] || continue; \
		gh release upload "$$tag" "$$f"; \
		echo "  uploaded: $$(basename $$f)"; \
	done; \
	echo ""; \
	echo "release $$tag published."; \
	gh release view "$$tag" --web

.DEFAULT_GOAL := build
