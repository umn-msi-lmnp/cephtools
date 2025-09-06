#!/usr/bin/env bash
###############################################################################
# Plugin Loader System for cephtools
###############################################################################

# Get the directory where this script is located
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CEPHTOOLS_ROOT="$(dirname "$(dirname "${_SCRIPT_DIR}")")"

# Plugin directories
_PLUGIN_DIR="${_CEPHTOOLS_ROOT}/plugins"
_BUILD_PLUGIN_DIR="${_CEPHTOOLS_ROOT}/build/share/plugins"

# Array to store loaded plugins
declare -a _LOADED_PLUGINS=()

###############################################################################
# Plugin Discovery and Loading
###############################################################################

# _discover_plugins()
#
# Description:
#   Discover available plugins in the plugin directory
_discover_plugins() {
  local plugin_dir="${_BUILD_PLUGIN_DIR}"
  
  # Fall back to source directory if build directory doesn't exist
  if [[ ! -d "${plugin_dir}" ]]; then
    plugin_dir="${_PLUGIN_DIR}"
  fi
  
  if [[ ! -d "${plugin_dir}" ]]; then
    _debug printf "No plugin directory found at %s\\n" "${plugin_dir}"
    return 1
  fi
  
  _debug printf "Discovering plugins in %s\\n" "${plugin_dir}"
  
  for plugin_path in "${plugin_dir}"/*; do
    if [[ -d "${plugin_path}" ]]; then
      local plugin_name="$(basename "${plugin_path}")"
      local plugin_file="${plugin_path}/plugin.sh"
      
      if [[ -f "${plugin_file}" ]]; then
        _debug printf "Found plugin: %s\\n" "${plugin_name}"
        _LOADED_PLUGINS+=("${plugin_name}")
      fi
    fi
  done
}

# _load_plugin()
#
# Usage:
#   _load_plugin <plugin_name>
#
# Description:
#   Load a specific plugin by name
_load_plugin() {
  local plugin_name="${1:-}"
  
  if [[ -z "${plugin_name}" ]]; then
    _exit_1 printf "_load_plugin(): plugin name required\\n"
  fi
  
  local plugin_dir="${_BUILD_PLUGIN_DIR}"
  
  # Fall back to source directory if build directory doesn't exist
  if [[ ! -d "${plugin_dir}" ]]; then
    plugin_dir="${_PLUGIN_DIR}"
  fi
  
  local plugin_file="${plugin_dir}/${plugin_name}/plugin.sh"
  
  if [[ ! -f "${plugin_file}" ]]; then
    _exit_1 printf "Plugin '%s' not found at %s\\n" "${plugin_name}" "${plugin_file}"
  fi
  
  _debug printf "Loading plugin: %s from %s\\n" "${plugin_name}" "${plugin_file}"
  
  # Source the plugin file
  # shellcheck source=/dev/null
  source "${plugin_file}"
  
  # Validate plugin interface
  _validate_plugin_interface "${plugin_name}"
}

# _validate_plugin_interface()
#
# Usage:
#   _validate_plugin_interface <plugin_name>
#
# Description:
#   Validate that a plugin implements the required interface
_validate_plugin_interface() {
  local plugin_name="${1:-}"
  
  # Check required functions
  local required_functions=(
    "plugin_main"
    "plugin_describe"
  )
  
  for func in "${required_functions[@]}"; do
    if ! _function_exists "${func}"; then
      _exit_1 printf "Plugin '%s' missing required function: %s\\n" "${plugin_name}" "${func}"
    fi
  done
  
  _debug printf "Plugin '%s' interface validation passed\\n" "${plugin_name}"
}

# _list_available_plugins()
#
# Description:
#   List all available plugins
_list_available_plugins() {
  _discover_plugins
  
  if [[ ${#_LOADED_PLUGINS[@]} -eq 0 ]]; then
    printf "No plugins found\\n" >&2
    return 1
  fi
  
  printf "Available plugins:\\n"
  for plugin in "${_LOADED_PLUGINS[@]}"; do
    printf "  %s\\n" "${plugin}"
  done
}

# _plugin_exists()
#
# Usage:
#   _plugin_exists <plugin_name>
#
# Description:
#   Check if a plugin exists
_plugin_exists() {
  local plugin_name="${1:-}"
  
  if [[ -z "${plugin_name}" ]]; then
    return 1
  fi
  
  _discover_plugins
  _contains "${plugin_name}" "${_LOADED_PLUGINS[@]}"
}

###############################################################################
# Plugin Execution
###############################################################################

# _execute_plugin()
#
# Usage:
#   _execute_plugin <plugin_name> [arguments...]
#
# Description:
#   Execute a plugin with the given arguments
_execute_plugin() {
  local plugin_name="${1:-}"
  shift
  
  if [[ -z "${plugin_name}" ]]; then
    _exit_1 printf "_execute_plugin(): plugin name required\\n"
  fi
  
  # Load the plugin
  _load_plugin "${plugin_name}"
  
  # Execute the plugin's main function
  _debug printf "Executing plugin '%s' with arguments: %s\\n" "${plugin_name}" "${*}"
  plugin_main "${@}"
}

# _get_plugin_help()
#
# Usage:
#   _get_plugin_help <plugin_name>
#
# Description:
#   Get help text for a specific plugin
_get_plugin_help() {
  local plugin_name="${1:-}"
  
  if [[ -z "${plugin_name}" ]]; then
    _exit_1 printf "_get_plugin_help(): plugin name required\\n"
  fi
  
  # Load the plugin
  _load_plugin "${plugin_name}"
  
  # Get the plugin's help text
  plugin_describe
}