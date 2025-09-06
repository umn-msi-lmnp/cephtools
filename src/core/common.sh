#!/usr/bin/env bash
###############################################################################
# Common utilities and functions for cephtools
# Extracted from original head_1 and head_2 files
###############################################################################

###############################################################################
# Strict Mode
###############################################################################

# Treat unset variables and parameters other than the special parameters '@' or
# '*' as an error when performing parameter expansion. 
set -o nounset

# Exit immediately if a pipeline returns non-zero.
set -o errexit

# Print a helpful message if a pipeline with non-zero exit code causes the
# script to exit as described above.
trap 'echo "Aborting due to errexit on line $LINENO. Exit code: $?" >&2' ERR

# Allow the above trap be inherited by all functions in the script.
set -o errtrace

# Return value of a pipeline is the value of the last (rightmost) command to
# exit with a non-zero status, or zero if all commands in the pipeline exit
# successfully.
set -o pipefail

# Set $IFS to only newline and tab.
IFS=$'\n\t'

###############################################################################
# Globals
###############################################################################

# This program's basename.
_ME="$(basename "${0}")"

# The subcommand to be run by default, when no subcommand name is specified.
DEFAULT_SUBCOMMAND="${DEFAULT_SUBCOMMAND:-help}"

###############################################################################
# Debug
###############################################################################

# _debug()
#
# Usage:
#   _debug <command> <options>...
#
# Description:
#   Execute a command and print to standard error. The command is expected to
#   print a message and should typically be either `echo`, `printf`, or `cat`.
__DEBUG_COUNTER=0
_debug() {
  if ((${_USE_DEBUG:-0}))
  then
    __DEBUG_COUNTER=$((__DEBUG_COUNTER+1))
    {
      # Prefix debug message with "bug (U+1F41B)"
      printf "🐛  %s " "${__DEBUG_COUNTER}"
      "${@}"
      printf "―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――\\n"
    } 1>&2
  fi
}

###############################################################################
# Error Messages
###############################################################################

# _exit_1()
#
# Usage:
#   _exit_1 <command>
#
# Description:
#   Exit with status 1 after executing the specified command with output
#   redirected to standard error. The command is expected to print a message
#   and should typically be either `echo`, `printf`, or `cat`. Prints the parent 
#   function name in brackets in red.
_exit_1() {
  {
    printf "[%s %s %s] " "${_ME}" "${FUNCNAME[1]}" "$(tput setaf 1)ERROR$(tput sgr0)"
    "${@}"
  } 1>&2
  exit 1
}

# _warn()
#
# Usage:
#   _warn <command>
#
# Description:
#   Print the specified command with output redirected to standard error.
#   The command is expected to print a message and should typically be either
#   `echo`, `printf`, or `cat`. Prints the parent function name in brackets in red.
_warn() {
  {
    printf "[%s %s %s] " "${_ME}" "${FUNCNAME[1]}" "$(tput setaf 1)WARNING$(tput sgr0)"
    "${@}"
  } 1>&2
}

# _info()
#
# Usage:
#   _info <command>
#
# Description:
#   Print the specified command with output redirected to standard error.
#   The command is expected to print a message and should typically be either
#   `echo`, `printf`, or `cat`. Prints the parent function name in brackets.
_info() {
  {
    printf "[%s %s INFO] " "${_ME}" "${FUNCNAME[1]}"
    "${@}"
  } 1>&2
}

# _verb()
#
# Usage:
#   _verb <command> <options>...
#
# Description:
#   Execute a command and print to standard error. The command is expected to
#   print a message and should typically be either `echo`, `printf`, or `cat`.
_verb() {
  if ((${_USE_VERBOSE:-0}))
  then
    {
      printf "[%s %s INFO] " "${_ME}" "${FUNCNAME[1]}"
      "${@}"
    } 1>&2
  fi
}

###############################################################################
# Utility Functions
###############################################################################

# _function_exists()
#
# Usage:
#   _function_exists <name>
#
# Description:
#   Returns 0 if the function exists, 1 otherwise.
_function_exists() {
  [ "$(type -t "${1}")" = 'function' ]
}

# _contains()
#
# Usage:
#   _contains <query> <list-item>...
#
# Description:
#   Returns 0 if the specified <query> is contained in the list of
#   <list-item>s, 1 otherwise.
_contains() {
  local _query="${1:-}"
  shift

  if [[ -z "${_query}" ]] || [[ -z "${*:-}" ]]
  then
    return 1
  fi

  for __element in "${@}"
  do
    [[ "${__element}" == "${_query}" ]] && return 0
  done

  return 1
}

# _readlink()
#
# Usage:
#   _readlink <path>
#
# Description:
#   Get absolute path from relative path.
_readlink() {
  _target_file="${1}"

  cd "$(dirname "${_target_file}")"
  _target_file="$(basename "${_target_file}")"

  # Iterate down a (possible) chain of symlinks
  while [ -L "${_target_file}" ]
  do
    _target_file="$(readlink "${_target_file}")"
    cd "$(dirname "${_target_file}")"
    _target_file="$(basename "${_target_file}")"
  done

  # Compute the canonicalized name by finding the physical path
  # for the directory we're in and appending the target file.
  _phys_dir="$(pwd -P)"
  _result="${_phys_dir}/${_target_file}"
  printf "%s\\n" "${_result}"
}

###############################################################################
# AWS/S3 Helpers
###############################################################################

# _setup_aws_credentials()
#
# Description:
#   Set up AWS credentials for ceph access using s3info if available
_setup_aws_credentials() {
  if command -v s3info >/dev/null 2>&1; then
    AWS_ACCESS_KEY="$(s3info --keys | awk '{print $1}')"
    AWS_SECRET_KEY="$(s3info --keys | awk '{print $2}')"
    export AWS_ACCESS_KEY AWS_SECRET_KEY
    _debug printf "AWS credentials set up from s3info\\n"
  else
    _warn printf "s3info command not available for credential setup\\n"
  fi
}

# _setup_rclone_credentials()
#
# Description:
#   Set up rclone credentials for temporary remote configuration
_setup_rclone_credentials() {
  if command -v s3info >/dev/null 2>&1; then
    RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID="$(s3info --keys | awk '{print $1}')"
    RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY="$(s3info --keys | awk '{print $2}')"
    export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY
    export RCLONE_CONFIG_MYREMOTE_TYPE="s3"
    export RCLONE_CONFIG_MYREMOTE_PROVIDER="Ceph"
    export RCLONE_CONFIG_MYREMOTE_ENDPOINT="https://s3.msi.umn.edu"
    _debug printf "Rclone credentials configured\\n"
  else
    _warn printf "s3info command not available for rclone credential setup\\n"
  fi
}