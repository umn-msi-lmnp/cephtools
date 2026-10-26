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
COMPLETION_FILE="${BUILD_DIR}/share/bash-completion/completions/cephtools"

echo "Running plugin tests..."
echo "Project root: ${PROJECT_ROOT}"
echo "Cephtools binary: ${CEPHTOOLS_BIN}"

# Test 1: Check if binary exists
if [[ ! -f "${CEPHTOOLS_BIN}" ]]; then
  echo "ERROR: cephtools binary not found. Run 'make' first."
  exit 1
fi
echo "PASS: Binary exists"

# Test 2: Basic help command
echo "Testing help command..."
if ! "${CEPHTOOLS_BIN}" help >/dev/null 2>&1; then
  echo "ERROR: Help command failed"
  exit 1
fi
echo "PASS: Help command works"

# Test 3: Version command
echo "Testing version command..."
if ! "${CEPHTOOLS_BIN}" version >/dev/null 2>&1; then
  echo "ERROR: Version command failed"
  exit 1
fi
echo "PASS: Version command works"

# Test 4: Subcommands list
echo "Testing subcommands list..."
if ! "${CEPHTOOLS_BIN}" subcommands >/dev/null 2>&1; then
  echo "ERROR: Subcommands command failed"
  exit 1
fi
echo "PASS: Subcommands command works"

# Test 5: Plugin discovery
echo "Testing plugin discovery..."
plugin_count=$("${CEPHTOOLS_BIN}" subcommands --raw | wc -l)
if [[ ${plugin_count} -eq 0 ]]; then
  echo "WARNING: No plugins discovered"
else
  echo "PASS: Discovered ${plugin_count} plugin(s)"
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
    echo "  PASS: Help works for plugin: ${plugin}"
  fi
done < <("${CEPHTOOLS_BIN}" subcommands --raw)

# Test 7: Bash completion
echo "Testing Bash completion..."
if [[ ! -f "${COMPLETION_FILE}" ]]; then
  echo "ERROR: Bash completion file not found"
  exit 1
fi

if [[ -f /usr/share/bash-completion/bash_completion ]]; then
  completion_test_dir=$(mktemp --directory "${TMPDIR:-/tmp}/cephtools-completion.XXXXXX")
  trap 'rm -rf "${completion_test_dir}"' EXIT
  mkdir -p "${completion_test_dir}/completions"
  ln -s "${COMPLETION_FILE}" "${completion_test_dir}/completions/cephtools"

  if ! BASH_COMPLETION_USER_DIR="${completion_test_dir}" bash --noprofile --norc -c '
    source /usr/share/bash-completion/bash_completion
    __load_completion cephtools
    complete -p cephtools | grep -q -- "complete -F _cephtools cephtools"

    COMP_WORDS=(cephtools buc)
    COMP_CWORD=1
    _cephtools
    [[ " ${COMPREPLY[*]} " == *" bucketpolicy "* ]]
  '; then
    echo "ERROR: Bash did not load completion from the standard per-user location"
    exit 1
  fi
else
  echo "WARNING: bash-completion is unavailable; skipping lazy-loading test"
fi

# shellcheck source=/dev/null
source "${COMPLETION_FILE}"

COMP_WORDS=(cephtools buc)
COMP_CWORD=1
_cephtools
if [[ " ${COMPREPLY[*]} " != *" bucketpolicy "* ]]; then
  echo "ERROR: Subcommand completion did not offer bucketpolicy"
  exit 1
fi

COMP_WORDS=(cephtools bucketpolicy --p)
COMP_CWORD=2
_cephtools
if [[ " ${COMPREPLY[*]} " != *" --policy "* ]]; then
  echo "ERROR: Option completion did not offer --policy"
  exit 1
fi

COMP_WORDS=(cephtools bucketpolicy --policy GROUP_)
COMP_CWORD=3
_cephtools
if [[ " ${COMPREPLY[*]} " != *" GROUP_READ "* ]] || \
   [[ " ${COMPREPLY[*]} " != *" GROUP_READ_WRITE "* ]]; then
  echo "ERROR: Policy value completion did not offer GROUP policies"
  exit 1
fi

COMP_WORDS=(cephtools vast2ceph --path "${PROJECT_ROOT}/s")
COMP_CWORD=3
_cephtools
if [[ " ${COMPREPLY[*]} " != *" ${PROJECT_ROOT}/src "* ]]; then
  echo "ERROR: Directory completion did not offer src"
  exit 1
fi

COMP_WORDS=(cephtools vast2ceph -p "${PROJECT_ROOT}/s")
COMP_CWORD=3
_cephtools
if [[ " ${COMPREPLY[*]} " != *" ${PROJECT_ROOT}/src "* ]]; then
  echo "ERROR: Short path option completion did not offer src"
  exit 1
fi

echo "PASS: Bash completion works"

echo ""
echo "All tests passed!"
