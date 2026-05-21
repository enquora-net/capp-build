# Makefile
# capp-build
#
# Orchestrates the Lisette build pipeline with local capp-parse dependency.
#
# Lisette regenerates target/go.mod on every run. GOFLAGS points Go at a
# durable module overlay that keeps private local replacements visible during
# Lisette's internal go mod tidy/build steps.

BINARY        := capp-build
TARGET        := target
LOCAL_MOD     := $(abspath lisette.local.mod)
GO_ENV        := GOFLAGS=-modfile=$(LOCAL_MOD)

.PHONY: all run clean

all: run

run:
	$(GO_ENV) lis run

clean:
	rm -rf $(TARGET)/vendor
	rm -f $(TARGET)/go.sum
