#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
BUILD_DIR="${PROJECT_ROOT}/build"
MODULEFILE="${BUILD_DIR}/modulefile"

if ! type module >/dev/null 2>&1; then
    for init_script in \
        /etc/profile.d/modules.sh \
        /usr/share/Modules/init/bash \
        /usr/share/modules/init/bash; do
        if [[ -f "${init_script}" ]]; then
            # shellcheck source=/dev/null
            source "${init_script}"
            break
        fi
    done
fi

if ! type module >/dev/null 2>&1; then
    printf 'ERROR: Environment Modules is required for the modulefile test\n' >&2
    exit 1
fi

if [[ ! -f "${MODULEFILE}" ]]; then
    printf 'ERROR: modulefile not found at %s; run make first\n' "${MODULEFILE}" >&2
    exit 1
fi

TEST_HOME="$(mktemp --directory "${TMPDIR:-/tmp}/cephtools-module.XXXXXX")"
ORIGINAL_HOME="${HOME}"
ORIGINAL_PATH="${PATH}"
module_loaded=false

cleanup() {
    if [[ "${module_loaded}" == true ]]; then
        module unload "${MODULEFILE}" >/dev/null 2>&1 || true
    fi
    HOME="${ORIGINAL_HOME}"
    PATH="${ORIGINAL_PATH}"
    rm -rf "${TEST_HOME}"
}
trap cleanup EXIT

HOME="${TEST_HOME}"
module load "${MODULEFILE}"
module_loaded=true

if [[ "$(command -v cephtools)" != "${BUILD_DIR}/bin/cephtools" ]]; then
    printf 'ERROR: modulefile did not expose the built cephtools executable\n' >&2
    exit 1
fi

if ! declare -F _cephtools >/dev/null; then
    printf 'ERROR: modulefile did not load the Bash completion function\n' >&2
    exit 1
fi

if ! complete -p cephtools 2>/dev/null | grep -q -- 'complete -F _cephtools cephtools'; then
    printf 'ERROR: modulefile did not register Bash completion\n' >&2
    exit 1
fi

if [[ -e "${HOME}/.local/share/bash-completion/completions/cephtools" ]]; then
    printf 'ERROR: modulefile created a per-user completion file\n' >&2
    exit 1
fi

module unload "${MODULEFILE}"
module_loaded=false

if [[ "${PATH}" != "${ORIGINAL_PATH}" ]]; then
    printf 'ERROR: module unload did not restore PATH\n' >&2
    exit 1
fi

if declare -F _cephtools >/dev/null; then
    printf 'ERROR: module unload did not remove the completion function\n' >&2
    exit 1
fi

if complete -p cephtools >/dev/null 2>&1; then
    printf 'ERROR: module unload did not remove the completion registration\n' >&2
    exit 1
fi

printf 'Modulefile load and unload tests passed\n'
