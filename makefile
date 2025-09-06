SHELL := /bin/bash

# Paths (make configurable, remove hardcoded paths)
PREFIX     := ./build
DESTDIR    :=
BUILD      := $(DESTDIR)$(PREFIX)

# Git Metadata
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
.PHONY: test-all test-deps test-integration test-errors test-compatibility test-quick

all: core plugins validate-plugins

# Core framework with proper separation
core: $(BUILD)/bin/cephtools

$(BUILD)/bin/cephtools: $(CORE_FILES)
	mkdir -p $(dir $@)
	# Combine core files with proper separation
	echo '#!/usr/bin/env bash' > $@
	echo '' >> $@
	cat src/core/common.sh >> $@
	echo '' >> $@
	# Process version.sh with git variable substitution
	sed -e 's|^GIT_CURRENT_BRANCH=.*|GIT_CURRENT_BRANCH="$(GIT_CURRENT_BRANCH)"|' \
	    -e 's|^GIT_LATEST_COMMIT=.*|GIT_LATEST_COMMIT="$(GIT_LATEST_COMMIT)"|' \
	    -e 's|^GIT_LATEST_COMMIT_SHORT=.*|GIT_LATEST_COMMIT_SHORT="$(GIT_LATEST_COMMIT_SHORT)"|' \
	    -e 's|^GIT_LATEST_COMMIT_DIRTY=.*|GIT_LATEST_COMMIT_DIRTY="$(GIT_LATEST_COMMIT_DIRTY)"|' \
	    -e 's|^GIT_LATEST_COMMIT_DATETIME=.*|GIT_LATEST_COMMIT_DATETIME="$(GIT_LATEST_COMMIT_DATETIME)"|' \
	    -e 's|^GIT_REMOTE=.*|GIT_REMOTE="$(GIT_REMOTE)"|' \
	    src/core/version.sh >> $@
	echo '' >> $@
	cat src/core/plugin-loader.sh >> $@
	echo '' >> $@
	cat src/core/cephtools-simple.sh >> $@
	chmod +x $@

# Plugin system
plugins: $(PLUGIN_TARGETS)

$(BUILD)/share/plugins/%/plugin.sh: src/plugins/%/plugin.sh
	mkdir -p $(dir $@)
	cp $< $@
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
test-all: all
	@echo "Running comprehensive test suite..."
	@chmod +x tests/run-all-tests.sh
	@tests/run-all-tests.sh

test-quick: all  
	@echo "Running quick tests (basic functionality)..."
	@chmod +x tests/run-all-tests.sh
	@tests/run-all-tests.sh basic

test-deps: all
	@echo "Running dependency validation tests..."
	@chmod +x tests/test-dependencies.sh
	@tests/test-dependencies.sh

test-integration: all
	@echo "Running integration tests..."
	@chmod +x tests/test-integration.sh  
	@tests/test-integration.sh

test-errors: all
	@echo "Running error scenario tests..."
	@chmod +x tests/test-error-scenarios.sh
	@tests/test-error-scenarios.sh

test-compatibility: all
	@echo "Running system compatibility tests..."
	@chmod +x tests/test-compatibility.sh
	@tests/test-compatibility.sh

# Help target for testing
test-help:
	@echo "Available test targets:"
	@echo "  test-all          - Run all test suites (comprehensive)"
	@echo "  test-quick        - Run basic functionality tests only"
	@echo "  test-deps         - Run dependency validation tests"
	@echo "  test-integration  - Run integration tests with mocks"
	@echo "  test-errors       - Run error scenario tests"
	@echo "  test-compatibility- Run system compatibility tests"
	@echo "  test              - Legacy basic tests"
	@echo "  comprehensive-test- Legacy comprehensive tests"
	@echo ""
	@echo "Test options (via run-all-tests.sh):"
	@echo "  make test-all                    # All tests"
	@echo "  ./tests/run-all-tests.sh --quiet # Run quietly"
	@echo "  ./tests/run-all-tests.sh basic integration # Specific suites"

# Clean
clean:
	rm -rf $(BUILD)