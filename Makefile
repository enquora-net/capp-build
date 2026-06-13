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

.PHONY: all run clean bump-parse gate

all: run

run:
	lis run

# Phase 8 tier gate: build, compile toolchain_test in debug mode, and
# byte-compare our main.j record against the legacy oracle (S stripped).
gate:
	lis build
	"$(TARGET)/$(BINARY)" build --mode debug "$(TOOLCHAIN_TEST)"
	python3 payload_oracle.py diff \
		"$(TOOLCHAIN_TEST)/Build/toolchain_test.build/Debug/Browser.environment/Sources/main.j" \
		"$(TOOLCHAIN_TEST)/Build/capp-build.build/Debug/Sources/main.j"

# Tier B progress check: AppController.j against the legacy oracle.
# EXPECTED TO DIVERGE until tier C lands — the divergence must sit exactly
# at the awakeFromCib message send (legacy shows `((___r1 = self.theWindow)`,
# ours the deferred send's bare `;`).  Anything earlier is a tier B defect.
# --t-only: the record's t-length field necessarily differs while the
# payload is incomplete, so compare the payloads themselves.
gate-b:
	-python3 payload_oracle.py diff --t-only \
		"$(TOOLCHAIN_TEST)/Build/toolchain_test.build/Debug/Browser.environment/Sources/AppController.j" \
		"$(TOOLCHAIN_TEST)/Build/capp-build.build/Debug/Sources/AppController.j"

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
