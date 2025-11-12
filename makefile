SHELL := /bin/bash

# Paths (make configurable, remove hardcoded paths)
PREFIX     := ./build
DESTDIR    :=
BUILD      := $(DESTDIR)$(PREFIX)

# ---------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------

# Default target
.DEFAULT_GOAL := all

.PHONY: version .FORCE

# Read semantic version from version.txt file in src/
SEMANTIC_VERSION := $(shell source src/version.txt && echo $$SEMANTIC_VERSION)

# Generate essential version info (enhanced from current)
GIT_COMMIT_SHORT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
GIT_LATEST_COMMIT_SHORT := $(GIT_COMMIT_SHORT)
GIT_LATEST_COMMIT_DATETIME := $(shell git log -1 --format="%cd" --date=iso 2>/dev/null || echo "unknown")
GIT_CURRENT_BRANCH := $(shell git branch --show-current 2>/dev/null || echo "unknown")
GIT_WEB_URL := $(shell git remote get-url origin 2>/dev/null | sed 's/git@github\.com:/https:\/\/github.com\//' | sed 's/git@github\.umn\.edu:/https:\/\/github.umn.edu\//' | sed 's/\.git$$//' || echo "unknown")
GIT_DIRTY := $(shell git diff --quiet 2>/dev/null || echo "-dirty")
BUILD_DATE := $(shell date -Iseconds)
VERSION_SHORT := $(SEMANTIC_VERSION)_$(GIT_COMMIT_SHORT)$(GIT_DIRTY)

# Write out version info
VERSION_FILE := $(PREFIX)/version.txt

$(VERSION_FILE): .FORCE
	@mkdir -p $(dir $@)
	@echo "SEMANTIC_VERSION=$(SEMANTIC_VERSION)" > $@
	@echo "VERSION_SHORT=$(VERSION_SHORT)" >> $@
	@echo "BUILD_DATE=$(BUILD_DATE)" >> $@
	@echo "GIT_CURRENT_BRANCH=$(GIT_CURRENT_BRANCH)" >> $@
	@echo "GIT_LATEST_COMMIT_DATETIME=$(GIT_LATEST_COMMIT_DATETIME)" >> $@
	@echo "GIT_WEB_URL=$(GIT_WEB_URL)" >> $@

version: $(VERSION_FILE) ## Generate version info and write to $(PREFIX)/version.txt
	@cat $(VERSION_FILE)

.FORCE:

# Legacy Git Metadata (for backward compatibility)
GIT_CURRENT_BRANCH        := $(shell git symbolic-ref --short HEAD)
GIT_LATEST_COMMIT         := $(shell git rev-parse HEAD)
GIT_LATEST_COMMIT_SHORT   := $(shell echo $(GIT_LATEST_COMMIT) | cut -c1-7)
GIT_LATEST_COMMIT_DIRTY   := $(shell git diff --quiet || echo "-dirty")
GIT_LATEST_COMMIT_DATETIME:= $(shell git show -s --format="%cI" $(GIT_LATEST_COMMIT))
GIT_REMOTE                := $(shell git ls-remote --get-url)

# Plugin Discovery
PLUGIN_DIRS := $(wildcard src/plugins/*)
PLUGIN_NAMES := $(notdir $(PLUGIN_DIRS))
PLUGIN_TARGETS := $(PLUGIN_NAMES:%=$(BUILD)/share/plugins/%/plugin.sh)

# Core Files
CORE_FILES := src/core/common.sh \
              src/core/version.sh \
              src/core/plugin-loader.sh \
              src/core/cephtools-simple.sh

# Top-level Targets
.PHONY: all clean plugins core test validate-plugins list-plugins show-config comprehensive-test
.PHONY: test-all test-deps test-integration test-errors test-compatibility test-quick test-empty-dirs test-vignette-e2e

# Default target - build everything
all: version core plugins validate-plugins

# Core framework with proper separation
core: $(BUILD)/bin/cephtools

$(BUILD)/bin/cephtools: $(CORE_FILES) $(VERSION_FILE)
	mkdir -p $(dir $@)
	# Combine core files with proper separation
	echo '#!/usr/bin/env bash' > $@
	echo '' >> $@
	cat src/core/common.sh >> $@
	echo '' >> $@
	# Process version.sh with comprehensive version substitution
	sed -e 's|^SEMANTIC_VERSION=.*|SEMANTIC_VERSION="$(SEMANTIC_VERSION)"|' \
	    -e 's|^BUILD_DATE=.*|BUILD_DATE="$(BUILD_DATE)"|' \
	    -e 's|^GIT_CURRENT_BRANCH=.*|GIT_CURRENT_BRANCH="$(GIT_CURRENT_BRANCH)"|' \
	    -e 's|^GIT_LATEST_COMMIT=.*|GIT_LATEST_COMMIT="$(GIT_LATEST_COMMIT)"|' \
	    -e 's|^GIT_LATEST_COMMIT_SHORT=.*|GIT_LATEST_COMMIT_SHORT="$(GIT_LATEST_COMMIT_SHORT)"|' \
	    -e 's|^GIT_LATEST_COMMIT_DIRTY=.*|GIT_LATEST_COMMIT_DIRTY="$(GIT_DIRTY)"|' \
	    -e 's|^GIT_LATEST_COMMIT_DATETIME=.*|GIT_LATEST_COMMIT_DATETIME="$(GIT_LATEST_COMMIT_DATETIME)"|' \
	    -e 's|^GIT_REMOTE=.*|GIT_REMOTE="$(GIT_REMOTE)"|' \
	    -e 's|^VERSION_SHORT=.*|VERSION_SHORT="$(VERSION_SHORT)"|' \
	    src/core/version.sh >> $@
	echo '' >> $@
	cat src/core/plugin-loader.sh >> $@
	echo '' >> $@
	cat src/core/cephtools-simple.sh >> $@
	chmod +x $@

# Plugin system
plugins: $(PLUGIN_TARGETS)

$(BUILD)/share/plugins/%/plugin.sh: src/plugins/%/plugin.sh $(VERSION_FILE)
	mkdir -p $(dir $@)
	sed -e 's|@VERSION_SHORT@|$(VERSION_SHORT)|g' \
	    -e 's|@SEMANTIC_VERSION@|$(SEMANTIC_VERSION)|g' \
	    -e 's|@BUILD_DATE@|$(BUILD_DATE)|g' \
	    -e 's|@GIT_CURRENT_BRANCH@|$(GIT_CURRENT_BRANCH)|g' \
	    -e 's|@GIT_LATEST_COMMIT_SHORT@|$(GIT_LATEST_COMMIT_SHORT)|g' \
	    -e 's|@GIT_LATEST_COMMIT_DIRTY@|$(GIT_DIRTY)|g' \
	    -e 's|@GIT_LATEST_COMMIT_DATETIME@|$(GIT_LATEST_COMMIT_DATETIME)|g' \
	    -e 's|@GIT_WEB_URL@|$(GIT_WEB_URL)|g' \
	    $< > $@
	chmod +x $@

# Plugin validation
validate-plugins: plugins
	@echo "Validating plugins..."
	@for plugin in $(PLUGIN_DIRS); do \
		plugin_name=$$(basename $$plugin); \
		echo "Validating $$plugin_name..."; \
		if [ -f "$$plugin/plugin.sh" ]; then \
			if ! grep -q "plugin_main" "$$plugin/plugin.sh"; then \
				echo "ERROR: Plugin $$plugin_name missing plugin_main function"; \
				exit 1; \
			fi; \
			if ! grep -q "plugin_describe" "$$plugin/plugin.sh"; then \
				echo "ERROR: Plugin $$plugin_name missing plugin_describe function"; \
				exit 1; \
			fi; \
			echo "✓ Plugin $$plugin_name validated"; \
		else \
			echo "ERROR: Plugin $$plugin_name missing plugin.sh file"; \
			exit 1; \
		fi; \
	done
	@echo "All plugins validated successfully"

# Testing
test: all
	@echo "Testing cephtools help..."
	@./$(BUILD)/bin/cephtools help || echo "Help test failed"
	@echo "Testing plugin discovery..."
	@./$(BUILD)/bin/cephtools subcommands || echo "Plugin discovery test failed"
	@echo "Basic tests completed"

# Create test outputs directory
test-setup:
	@mkdir -p test_outputs
	@echo "Test outputs directory created: test_outputs"

# Comprehensive testing
comprehensive-test: all
	@echo "Running comprehensive tests..."
	@echo "=== Testing Core Functionality ==="
	@./$(BUILD)/bin/cephtools --version
	@./$(BUILD)/bin/cephtools help
	@echo ""
	@echo "=== Testing Plugin Discovery ==="
	@./$(BUILD)/bin/cephtools subcommands
	@echo ""
	@echo "=== Testing Individual Plugin Help ==="
	@for plugin in $(PLUGIN_NAMES); do \
		echo "Testing help for $$plugin..."; \
		./$(BUILD)/bin/cephtools help $$plugin >/dev/null || echo "ERROR: Help failed for $$plugin"; \
	done
	@echo ""
	@echo "All comprehensive tests completed ✅"

# Helper targets for development
list-plugins:
	@echo "Available plugins:"
	@for plugin in $(PLUGIN_NAMES); do echo "  $$plugin"; done

show-config:
	@echo "Build Configuration:"
	@echo "  BUILD: $(BUILD)"
	@echo "  PREFIX: $(PREFIX)"
	@echo "  PLUGIN_NAMES: $(PLUGIN_NAMES)"
	@echo "  GIT_CURRENT_BRANCH: $(GIT_CURRENT_BRANCH)"

# Enhanced Testing System
test-all: all test-setup
	@echo "Running comprehensive test suite..."
	@chmod +x tests/run-all-tests.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/run-all-tests.sh

test-quick: all test-setup
	@echo "Running quick tests (basic functionality)..."
	@chmod +x tests/run-all-tests.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/run-all-tests.sh basic

test-deps: all test-setup
	@echo "Running dependency validation tests..."
	@chmod +x tests/test-dependencies.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-dependencies.sh

test-integration: all test-setup
	@echo "Running integration tests..."
	@chmod +x tests/test-integration.sh  
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-integration.sh

test-errors: all test-setup
	@echo "Running error scenario tests..."
	@chmod +x tests/test-error-scenarios.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-error-scenarios.sh

test-compatibility: all test-setup
	@echo "Running system compatibility tests..."
	@chmod +x tests/test-compatibility.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-compatibility.sh

test-real-s3: all test-setup
	@echo "Running real S3 integration tests..."
	@chmod +x tests/test-real-s3-integration.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-real-s3-integration.sh

test-empty-dirs: all test-setup
	@echo "Running empty directory flag tests..."
	@chmod +x tests/test-empty-dirs-flag.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-empty-dirs-flag.sh

test-permissions: all test-setup
	@echo "Running file permission handling tests..."
	@chmod +x tests/test-permission-handling.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-permission-handling.sh

test-vignette-e2e: all test-setup
	@echo "Running complete vignette workflow end-to-end test..."
	@chmod +x tests/test-vignette-panfs2ceph-e2e.sh
	@CEPHTOOLS_TEST_OUTPUT_DIR="$(PWD)/test_outputs" tests/test-vignette-panfs2ceph-e2e.sh

# Help target for testing
test-help:
	@echo "Available test targets:"
	@echo "  test-all          - Run all test suites (comprehensive)"
	@echo "  test-quick        - Run basic functionality tests only"
	@echo "  test-deps         - Run dependency validation tests"
	@echo "  test-integration  - Run integration tests with mocks"
	@echo "  test-errors       - Run error scenario tests"
	@echo "  test-compatibility- Run system compatibility tests"
	@echo "  test-real-s3      - Run real S3 integration tests (creates actual buckets)"
	@echo "  test-empty-dirs   - Run empty directory flag tests (--delete_empty_dirs)"
	@echo "  test-permissions  - Run file permission handling tests"
	@echo "  test-vignette-e2e - Run complete vignette workflow test (bucket + policy + all 3 scripts)"
	@echo "  test              - Legacy basic tests"
	@echo "  comprehensive-test- Legacy comprehensive tests"
	@echo ""
	@echo "Test options (via run-all-tests.sh):"
	@echo "  make test-all                    # All tests"
	@echo "  ./tests/run-all-tests.sh --quiet # Run quietly"
	@echo "  ./tests/run-all-tests.sh basic integration # Specific suites"
	@echo ""
	@echo "Cleanup targets:"
	@echo "  clean             - Remove build artifacts"
	@echo "  clean-tests       - Remove test output directory (test_outputs/)"
	@echo "  clean-all         - Remove all build and test artifacts"

# Clean
clean:
	rm -rf $(BUILD)

clean-tests:
	rm -rf test_outputs
	@echo "Test outputs directory cleaned"

clean-legacy-tests:
	rm -rf tests_outputs tests/outputs
	@echo "Legacy test directories cleaned"

clean-all: clean clean-tests clean-legacy-tests
	@echo "All build and test artifacts cleaned"