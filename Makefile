# Makefile
# capp-build
#
# Build orchestration and dependency-pin tooling.
#
# One-time environment, required for resolving the private capp-parse module
# (symptoms of their absence are noted):
#
#   go env -w GOPRIVATE=github.com/enquora-net/*
#       Keeps proxy.golang.org and sum.golang.org out of the resolution path.
#       Absent: fetch errors mentioning proxy.golang.org (404/410).
#
#   git config --global url."git@github.com:enquora-net/".insteadOf "https://github.com/enquora-net/"
#       Routes module fetches for the org over SSH.
#       Absent: "terminal prompts disabled" / "could not read Username".
#
# Updating the capp-parse pin (make bump-parse):
#   Pinning is by commit hash; the branch is irrelevant. Go resolves any
#   pushed commit by hash. Never pin @latest or @branch — those consult the
#   default branch and caching makes them non-deterministic.
#   The target verifies the local capp-parse HEAD is pushed, asks go for the
#   canonical pseudo-version, rewrites the pin in lisette.toml, shows the
#   diff, and rebuilds. Review is git diff; revert is git checkout.
#
# Portability: this Makefile assumes a POSIX shell and is not intended to
# run under Windows. The durable home for this orchestration is the
# cappuccino CLI, where it is written once and runs everywhere; the Makefile
# is development scaffolding until then.

BINARY       := capp-build
TARGET       := target
PARSE_DIR    := $(HOME)/Desktop/capp-parse
PARSE_MODULE := github.com/enquora-net/capp-parse

TOOLCHAIN_TEST := $(HOME)/Desktop/toolchain_test
TOOLCHAIN_REF  := $(HOME)/Desktop/toolchain_reference

.PHONY: all run clean bump-parse gate gate-release gate-archive

all: run

run:
	lis run

# Phase 8 tier gate: build, compile toolchain_test in debug mode, and
# byte-compare both per-file records against the legacy oracle (S stripped).
# Through tier C both files are byte-exact — the whole toolchain_test app
# round-trips.
LEGACY := $(TOOLCHAIN_TEST)/Build/toolchain_test.build/Debug/Browser.environment/Sources
OURS   := $(TOOLCHAIN_TEST)/Build/capp-build.build/Debug/Sources
LEGACY_RELEASE := $(TOOLCHAIN_TEST)/Build/toolchain_test.build/Release/Browser.environment/Sources
OURS_RELEASE   := $(TOOLCHAIN_TEST)/Build/capp-build.build/Release/Sources

gate:
	lis build
	"$(TARGET)/$(BINARY)" build --mode debug "$(TOOLCHAIN_TEST)"
	python3 payload_oracle.py diff "$(LEGACY)/main.j" "$(OURS)/main.j"
	python3 payload_oracle.py diff "$(LEGACY)/AppController.j" "$(OURS)/AppController.j"

# Tier E release gate: compile toolchain_test in release mode and byte-compare
# both per-file records against the legacy release oracle.  Prerequisite: the
# legacy release build must exist at $(LEGACY_RELEASE); produce it with
# the legacy jake toolchain: `cd $(TOOLCHAIN_TEST) && jake release`.
# The release form differs from debug in exactly two ways: no leading \n\n
# prologue in the t payload, and bare selector strings (no dtable comma
# artifact) in dispatch expressions.
gate-release:
	lis build
	"$(TARGET)/$(BINARY)" build --mode release "$(TOOLCHAIN_TEST)"
	python3 payload_oracle.py diff "$(LEGACY_RELEASE)/main.j" "$(OURS_RELEASE)/main.j"
	python3 payload_oracle.py diff "$(LEGACY_RELEASE)/AppController.j" "$(OURS_RELEASE)/AppController.j"

# Phase 9 archive gate: build, assemble the full application deliverable for
# toolchain_test in both debug and release modes, and byte-compare the
# assembled bundles against the reference oracle (toolchain_reference).
# toolchain_reference is a separate copy of toolchain_test built once with
# the legacy jake toolchain and left untouched; toolchain_test is the live
# test subject rebuilt by capp-build on each run.
#
# The assembled .sj bundles are compared; file-copied assets (Frameworks/,
# Resources/, index.html) are not byte-compared here — structural presence
# is verified by inspection.  Info.plist is intentionally excluded: the
# legacy oracle contains 280NPLIST format; capp-build writes XML until the
# conversion is implemented (see TODO in archive_application_http1).
REF_DEBUG_BUNDLE   := $(TOOLCHAIN_REF)/Build/Debug/toolchain_reference/Browser.environment/toolchain_reference.sj
REF_RELEASE_BUNDLE := $(TOOLCHAIN_REF)/Build/Release/toolchain_reference/Browser.environment/toolchain_reference.sj
OURS_DEBUG_BUNDLE   := $(TOOLCHAIN_TEST)/Build/Debug/toolchain_test/Browser.environment/toolchain_test.sj
OURS_RELEASE_BUNDLE := $(TOOLCHAIN_TEST)/Build/Release/toolchain_test/Browser.environment/toolchain_test.sj

gate-archive:
	lis build
	"$(TARGET)/$(BINARY)" build --mode debug "$(TOOLCHAIN_TEST)"
	python3 payload_oracle.py diff "$(REF_DEBUG_BUNDLE)" "$(OURS_DEBUG_BUNDLE)"
	"$(TARGET)/$(BINARY)" build --mode release "$(TOOLCHAIN_TEST)"
	python3 payload_oracle.py diff "$(REF_RELEASE_BUNDLE)" "$(OURS_RELEASE_BUNDLE)"

clean:
	rm -rf $(TARGET)/vendor
	rm -f $(TARGET)/go.sum

# Pin capp-parse at its current pushed HEAD, then rebuild.
# Fails loudly if HEAD has not been pushed: go can only resolve pushed
# commits, and an unpushed pin is the most common cause of "unknown revision".
bump-parse:
	@hash=$$(git -C "$(PARSE_DIR)" rev-parse HEAD) || exit 1; \
	upstream=$$(git -C "$(PARSE_DIR)" rev-parse '@{upstream}' 2>/dev/null); \
	if [ -z "$$upstream" ]; then \
		echo "error: capp-parse HEAD has no upstream — push the branch first"; exit 1; \
	fi; \
	if ! git -C "$(PARSE_DIR)" merge-base --is-ancestor "$$hash" "$$upstream"; then \
		echo "error: capp-parse HEAD ($$hash) is not pushed — push before pinning"; exit 1; \
	fi; \
	echo "resolving $(PARSE_MODULE)@$$hash ..."; \
	version=$$(cd "$(TARGET)" && go list -m "$(PARSE_MODULE)@$$hash" | awk '{print $$2}') || exit 1; \
	tmp=$$(mktemp); \
	sed "s|^\"$(PARSE_MODULE)\" = .*|\"$(PARSE_MODULE)\" = \"$$version\"|" lisette.toml > "$$tmp" \
		&& mv "$$tmp" lisette.toml; \
	git --no-pager diff -- lisette.toml; \
	lis run
