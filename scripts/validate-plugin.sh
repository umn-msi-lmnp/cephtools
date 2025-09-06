#!/usr/bin/env bash
###############################################################################
# Plugin Validation Script
# Validates that plugins follow the required interface
###############################################################################

set -euo pipefail

plugin_dir="${1:-}"

if [[ -z "${plugin_dir}" ]]; then
  echo "Usage: $0 <plugin_directory>" >&2
  exit 1
fi

if [[ ! -d "${plugin_dir}" ]]; then
  echo "Error: Plugin directory '${plugin_dir}' does not exist" >&2
  exit 1
fi

plugin_name="$(basename "${plugin_dir}")"
plugin_file="${plugin_dir}/plugin.sh"

echo "Validating plugin: ${plugin_name}"

# Check plugin.sh exists
if [[ ! -f "${plugin_file}" ]]; then
  echo "Error: Missing required file: ${plugin_file}" >&2
  exit 1
fi

# Check required functions
required_functions=(
  "plugin_main"
  "plugin_describe"
)

for func in "${required_functions[@]}"; do
  if ! grep -q "^${func}()" "${plugin_file}"; then
    echo "Error: Missing required function: ${func}" >&2
    exit 1
  fi
done

# Check plugin metadata
required_vars=(
  "PLUGIN_NAME"
  "PLUGIN_DESCRIPTION"
)

for var in "${required_vars[@]}"; do
  if ! grep -q "^${var}=" "${plugin_file}"; then
    echo "Warning: Missing recommended variable: ${var}" >&2
  fi
done

echo "✓ Plugin ${plugin_name} validation passed"