#!/usr/bin/env bash
###############################################################################
# Plugin Test Runner
# Basic tests for the plugin architecture
###############################################################################

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BUILD_DIR="${PROJECT_ROOT}/build"
CEPHTOOLS_BIN="${BUILD_DIR}/bin/cephtools"

echo "Running plugin tests..."
echo "Project root: ${PROJECT_ROOT}"
echo "Cephtools binary: ${CEPHTOOLS_BIN}"

# Test 1: Check if binary exists
if [[ ! -f "${CEPHTOOLS_BIN}" ]]; then
  echo "ERROR: cephtools binary not found. Run 'make' first."
  exit 1
fi
echo "✓ Binary exists"

# Test 2: Basic help command
echo "Testing help command..."
if ! "${CEPHTOOLS_BIN}" help >/dev/null 2>&1; then
  echo "ERROR: Help command failed"
  exit 1
fi
echo "✓ Help command works"

# Test 3: Version command
echo "Testing version command..."
if ! "${CEPHTOOLS_BIN}" version >/dev/null 2>&1; then
  echo "ERROR: Version command failed"
  exit 1
fi
echo "✓ Version command works"

# Test 4: Subcommands list
echo "Testing subcommands list..."
if ! "${CEPHTOOLS_BIN}" subcommands >/dev/null 2>&1; then
  echo "ERROR: Subcommands command failed"
  exit 1
fi
echo "✓ Subcommands command works"

# Test 5: Plugin discovery
echo "Testing plugin discovery..."
plugin_count=$("${CEPHTOOLS_BIN}" subcommands --raw | wc -l)
if [[ ${plugin_count} -eq 0 ]]; then
  echo "WARNING: No plugins discovered"
else
  echo "✓ Discovered ${plugin_count} plugin(s)"
fi

# Test 6: Test each plugin's help
echo "Testing individual plugin help..."
while IFS= read -r plugin; do
  if [[ -n "${plugin}" ]]; then
    echo "  Testing help for plugin: ${plugin}"
    if ! "${CEPHTOOLS_BIN}" help "${plugin}" >/dev/null 2>&1; then
      echo "  ERROR: Help failed for plugin ${plugin}"
      exit 1
    fi
    echo "  ✓ Help works for plugin: ${plugin}"
  fi
done < <("${CEPHTOOLS_BIN}" subcommands --raw)

echo ""
echo "All tests passed! ✅"