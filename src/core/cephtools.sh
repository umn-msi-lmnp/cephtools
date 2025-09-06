#!/usr/bin/env bash
###############################################################################
# cephtools - Main Entry Point
# 
# Plugin-based architecture for MSI ceph storage tools
###############################################################################

# Get the directory where this script is located
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###############################################################################
# Built-in Commands
###############################################################################

# help command
help() {
  local subcommand="${1:-}"
  
  if [[ -n "${subcommand}" ]]; then
    # Show help for specific subcommand/plugin
    if _plugin_exists "${subcommand}"; then
      _get_plugin_help "${subcommand}"
    else
      _exit_1 printf "Unknown subcommand: %s\\n" "${subcommand}"
    fi
  else
    # Show general help
    cat <<HEREDOC
cephtools

Tools for transferring data between panfs (tier1) and ceph (tier2) MSI storage.

Version: ${VERSION_SHORT}

Usage:
  ${_ME} <subcommand> [--subcommand-options] [<arguments>]
  ${_ME} -h | --help
  ${_ME} --version

Options:
  -h --help  Display this help information.
  --version  Display version information.

Help:
  ${_ME} help [<subcommand>]

Available subcommands:
HEREDOC
    
    # List available plugins
    _discover_plugins
    for plugin in "${_LOADED_PLUGINS[@]}"; do
      printf "  %s\\n" "${plugin}"
    done
  fi
}

# version command
version() {
  printf "%s\\n" "${VERSION_SHORT}"
}

# subcommands command
subcommands() {
  if [[ "${1:-}" == "--raw" ]]; then
    _discover_plugins
    printf "%s\\n" "${_LOADED_PLUGINS[@]}"
  else
    printf "Available subcommands:\\n"
    _discover_plugins
    for plugin in "${_LOADED_PLUGINS[@]}"; do
      printf "  %s\\n" "${plugin}"
    done
  fi
}

###############################################################################
# Main Function
###############################################################################

_main() {
  # Parse command line arguments
  local _subcommand="${1:-}"
  
  # Handle special cases
  case "${_subcommand}" in
    "" | "help" | "-h" | "--help")
      help "${2:-}"
      return 0
      ;;
    "version" | "--version")
      version
      return 0
      ;;
    "subcommands")
      shift
      subcommands "${@}"
      return 0
      ;;
  esac
  
  # Check if it's a plugin
  if _plugin_exists "${_subcommand}"; then
    shift  # Remove subcommand from arguments
    _execute_plugin "${_subcommand}" "${@}"
  else
    _exit_1 printf "Unknown subcommand: %s\\n\\nRun '%s help' for available commands.\\n" "${_subcommand}" "${_ME}"
  fi
}

###############################################################################
# Script Entry Point
###############################################################################

# Only run main if this script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _main "${@}"
fi