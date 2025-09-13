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

# s3cmd()
#
# Description:
#   Wrapper function that sources our corrected s3cmd script instead of the buggy system one
#   This fixes the "AWS_ACCESS_KEY: unbound variable" issue in /opt/msi/bin/s3cmd
s3cmd() {
    # Check if test environment has provided a mock override
    if [[ -n "${S3CMD_MOCK_OVERRIDE:-}" && -x "${S3CMD_MOCK_OVERRIDE}" ]]; then
        "${S3CMD_MOCK_OVERRIDE}" "$@"
        return $?
    fi
    
    # Create temporary corrected s3cmd script
    local temp_s3cmd_script=$(mktemp)
    cat > "$temp_s3cmd_script" << 'EOF'
#!/bin/bash

# Ensure vars always exist
: "${AWS_ACCESS_KEY:=}"
: "${AWS_SECRET_KEY:=}"
: "${S3CMD_CONFIG:=}"

if [ -f "$HOME/.s3cfg" ]; then
  # User created a custom config; it should have precedence.
  if [ "${S3CMD_CONFIG:-}" == '/etc/msi/s3cfg-generic' ]; then
    unset S3CMD_CONFIG
    unset AWS_ACCESS_KEY
    unset AWS_SECRET_KEY
  fi
  /usr/bin/s3cmd "$@"
else
  if [ -z "${AWS_ACCESS_KEY:-}" ]; then
    DATA=$(s3info --keys)
    if [[ $? -eq 0 ]]; then
      read -r ACCESS_KEY SECRET_KEY <<< "$DATA"
      export AWS_ACCESS_KEY=$ACCESS_KEY
      export AWS_SECRET_KEY=$SECRET_KEY
    fi
  fi

  if [ -z "${S3CMD_CONFIG:-}" ]; then
    export S3CMD_CONFIG='/etc/msi/s3cfg-generic'
  fi

  if [ -n "${AWS_ACCESS_KEY:-}" ]; then
    /usr/bin/s3cmd "$@"
  else
    >&2 echo "An error occurred fetching S3 credentials."
  fi
fi
EOF
    
    # Source the corrected script with the provided arguments
    chmod +x "$temp_s3cmd_script"
    "$temp_s3cmd_script" "$@"
    local exit_code=$?
    
    # Clean up
    rm -f "$temp_s3cmd_script"
    
    return $exit_code
}

# _check_rclone_version()
#
# Description:
#   Load the rclone/1.71.0-r1 module for consistent rclone version across all users
#   Uses --force flag to override any sticky modules
_check_rclone_version() {
    _info printf "Loading rclone module for consistent version...\\n"
    
    # Force load the preferred rclone module, overriding any conflicts
    if module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
        _verb printf "Successfully loaded rclone/1.71.0-r1 module with --force\\n"
    else
        _exit_1 printf "Failed to load rclone/1.71.0-r1 module even with --force flag\\n"
        return 1
    fi
    
    # Verify rclone is now available
    if ! command -v rclone >/dev/null 2>&1; then
        _exit_1 printf "rclone command not available after loading module\\n"
        return 1
    fi
    
    # Check and report rclone version
    local rclone_version=$(rclone --version 2>/dev/null | head -n 1 || echo "unknown")
    _verb printf "Using rclone: %s\\n" "$(command -v rclone)"
    _verb printf "Version: %s\\n" "$rclone_version"
}

###############################################################################
# Shared Plugin Functions
###############################################################################

# __validate_bucket_name()
#
# Usage:
#   __validate_bucket_name <bucket_name>
#
# Description:
#   Validates bucket name format and removes common problematic patterns
__validate_bucket_name() {
  local bucket_name="${1:-}"
  
  if [[ -z "$bucket_name" ]]; then
    _exit_1 printf "Bucket name cannot be empty\\n"
  fi
  
  # Remove trailing slash if present
  bucket_name="${bucket_name%/}"
  
  # Check if bucket name is now empty after removing slash
  if [[ -z "$bucket_name" ]]; then
    _exit_1 printf "Bucket name cannot be just a slash. Please provide a valid bucket name.\\n"
  fi
  
  # Warn about other potential issues
  if [[ "$bucket_name" == *"/"* ]]; then
    _warn printf "Bucket name contains slashes which may cause issues: '%s'\\n" "$bucket_name"
  fi
  
  printf "%s\\n" "$bucket_name"
}

# _validate_rclone_connectivity()
#
# Usage:
#   _validate_rclone_connectivity <remote> <bucket>
#
# Description:
#   Tests rclone connectivity and bucket access
_validate_rclone_connectivity() {
    local remote="${1:-}"
    local bucket="${2:-}"
    
    _info printf "Testing rclone connectivity...\\n"
    
    # Check if rclone is available
    if ! command -v rclone >/dev/null 2>&1; then
        _exit_1 printf "rclone command not found. Please ensure rclone is installed and in PATH.\\n"
        return 1
    fi
    
    # Test remote connectivity
    _verb printf "Testing remote: %s\\n" "$remote"
    if ! rclone lsd "$remote:" >/dev/null 2>&1; then
        _exit_1 printf "Cannot connect to remote '%s'. Check your rclone configuration.\\n" "$remote"
        return 1
    fi
    
    # Test bucket access
    _verb printf "Testing bucket access: %s\\n" "$bucket"
    if ! rclone lsd "$remote:$bucket" >/dev/null 2>&1; then
        _warn printf "Cannot access bucket '%s' on remote '%s'.\\n" "$bucket" "$remote"
        _warn printf "This may be normal if the bucket doesn't exist yet - it will be created during transfer.\\n"
    else
        _info printf "✓ Bucket is accessible: %s:%s\\n" "$remote" "$bucket"
    fi
    
    return 0
}

# _check_path_permissions()
#
# Usage:
#   _check_path_permissions <path>
#
# Description:
#   Performs comprehensive permission checks on the given path and its contents.
#   Returns 0 if all checks pass, 1 if issues are found.
_check_path_permissions() {
    local path="${1:-}"
    local issues_found=0
    local temp_log=$(mktemp)
    local readable_count=0
    local unreadable_count=0
    local total_count=0
    
    if [[ -z "$path" ]]; then
        _exit_1 printf "Path cannot be empty for permission check\\n"
        return 1
    fi
    
    _info printf "Checking file permissions for: %s\\n" "$path"
    
    # Check if path exists and is accessible
    if [[ ! -e "$path" ]]; then
        _warn printf "Path does not exist: %s\\n" "$path"
        return 1
    fi
    
    if [[ ! -r "$path" ]]; then
        _warn printf "Cannot read path: %s\\n" "$path"
        return 1
    fi
    
    # Check if we can list directory contents
    if [[ -d "$path" ]]; then
        if ! ls "$path" >/dev/null 2>&1; then
            _warn printf "Cannot list directory contents: %s\\n" "$path"
            return 1
        fi
        _verb printf "✓ Directory is readable: %s\\n" "$path"
    fi
    
    # Comprehensive file permission scan
    _info printf "Scanning file permissions (this may take a while for large directories)...\\n"
    
    # Create temporary files for counting
    local temp_readable=$(mktemp)
    local temp_unreadable=$(mktemp)
    
    # Find all items and check permissions
    find "$path" -type f -o -type d 2>/dev/null | while IFS= read -r item; do
        # Check if we can read the item
        if [[ -r "$item" ]]; then
            echo "1" >> "$temp_readable"
        else
            echo "1" >> "$temp_unreadable"
            printf "%s\\n" "$item" >> "$temp_log"
            
            # Show first few unreadable items immediately
            local current_unreadable_count=$(wc -l < "$temp_unreadable" 2>/dev/null || echo "0")
            if [[ $current_unreadable_count -le 5 ]]; then
                _warn printf "Cannot read: %s\\n" "$item"
            fi
        fi
        
        # For directories, also check if we can list contents
        if [[ -d "$item" && -r "$item" ]]; then
            if ! ls "$item" >/dev/null 2>&1; then
                printf "DIR_LIST_FAIL: %s\\n" "$item" >> "$temp_log"
                local current_unreadable_count=$(wc -l < "$temp_unreadable" 2>/dev/null || echo "0")
                if [[ $current_unreadable_count -le 5 ]]; then
                    _warn printf "Cannot list directory: %s\\n" "$item"
                fi
            fi
        fi
    done
    
    # Count results
    readable_count=$(wc -l < "$temp_readable" 2>/dev/null || echo "0")
    unreadable_count=$(wc -l < "$temp_unreadable" 2>/dev/null || echo "0")
    total_count=$((readable_count + unreadable_count))
    
    # Set issues_found flag
    if [[ $unreadable_count -gt 0 ]]; then
        issues_found=1
    fi
    
    # Clean up temporary count files
    rm -f "$temp_readable" "$temp_unreadable"
    
    # Report results
    _info printf "Permission scan complete:\\n"
    _info printf "  Total items: %d\\n" "$total_count"
    _info printf "  Readable: %d\\n" "$readable_count"
    _info printf "  Unreadable: %d\\n" "$unreadable_count"
    
    if [[ $issues_found -eq 1 ]]; then
        _warn printf "Found %d files/directories with permission issues\\n" "$unreadable_count"
        
        # Show summary of unreadable items
        if [[ -s "$temp_log" ]]; then
            local log_lines=$(wc -l < "$temp_log")
            _warn printf "Unreadable items logged. First 10:\\n"
            head -10 "$temp_log" | while IFS= read -r line; do
                _warn printf "  %s\\n" "$line"
            done
            
            if [[ $log_lines -gt 10 ]]; then
                _warn printf "  ... and %d more (check logs for details)\\n" $((log_lines - 10))
            fi
        fi
        
        _warn printf "Permission issues detected. These files will not be transferred.\\n"
    else
        _info printf "✓ All files and directories are readable\\n"
    fi
    
    # Clean up
    rm -f "$temp_log"
    
    return $issues_found
}

# _check_disk_space()
#
# Usage:
#   _check_disk_space <path> <log_dir>
#
# Description:
#   Checks available disk space for logging and temporary files
_check_disk_space() {
    local path="${1:-}"
    local log_dir="${2:-}"
    
    _info printf "Checking disk space...\\n"
    
    # Check space for log directory
    if [[ -n "$log_dir" ]]; then
        local log_parent=$(dirname "$log_dir")
        local log_space_kb=$(df "$log_parent" | awk 'NR==2 {print $4}')
        local log_space_mb=$((log_space_kb / 1024))
        
        _verb printf "Available space for logs: %d MB\\n" "$log_space_mb"
        
        if [[ $log_space_mb -lt 100 ]]; then
            _warn printf "Low disk space for logs: %d MB available\\n" "$log_space_mb"
            _warn printf "Consider specifying a different log directory with --log_dir\\n"
        fi
    fi
    
    # Check space in source path for temporary files (empty dir markers)
    if [[ -d "$path" ]]; then
        local source_space_kb=$(df "$path" | awk 'NR==2 {print $4}')
        local source_space_mb=$((source_space_kb / 1024))
        
        _verb printf "Available space at source: %d MB\\n" "$source_space_mb"
        
        if [[ $source_space_mb -lt 50 ]]; then
            _warn printf "Low disk space at source: %d MB available\\n" "$source_space_mb"
            _warn printf "This may affect creation of empty directory markers\\n"
        fi
    fi
}

# _run_preflight_checks()
#
# Usage:
#   _run_preflight_checks <path> <remote> <bucket> <log_dir> <dry_run> [check_permissions]
#
# Description:
#   Runs all pre-flight checks and returns 0 if everything looks good
#   The check_permissions parameter is optional and defaults to true for backward compatibility
_run_preflight_checks() {
    local path="${1:-}"
    local remote="${2:-}"
    local bucket="${3:-}"
    local log_dir="${4:-}"
    local dry_run="${5:-}"
    local check_permissions="${6:-true}"
    local checks_passed=0
    
    _info printf "\\n=== Pre-flight Checks ===\\n"
    
    # 1. Path accessibility and permissions (if enabled)
    if [[ "$check_permissions" == "true" ]]; then
        _info printf "1. Checking file permissions...\\n"
        if ! _check_path_permissions "${path}"; then
            if [[ -z "${dry_run}" ]]; then
                _exit_1 printf "❌ Permission check failed\\n"
                checks_passed=1
            else
                _warn printf "⚠️  Permission issues detected, but continuing with dry run\\n"
            fi
        else
            _info printf "✅ Permission check passed\\n"
        fi
    else
        _info printf "1. Skipping permission checks (read-only source)\\n"
    fi
    
    # 2. Disk space
    _info printf "2. Checking disk space...\\n"
    _check_disk_space "${path}" "${log_dir}"
    _info printf "✅ Disk space check completed\\n"
    
    # 3. rclone version check
    _info printf "3. Checking rclone version...\\n"
    _check_rclone_version
    _info printf "✅ rclone version check completed\\n"
    
    # 4. rclone connectivity (skip in dry run for speed)
    if [[ -z "${dry_run}" ]]; then
        _info printf "4. Testing rclone connectivity...\\n"
        if ! _validate_rclone_connectivity "${remote}" "${bucket}"; then
            _exit_1 printf "❌ rclone connectivity check failed\\n"
            checks_passed=1
        else
            _info printf "✅ rclone connectivity check passed\\n"
        fi
    else
        _info printf "4. Skipping rclone connectivity check (dry run mode)\\n"
    fi
    
    # 5. Estimate transfer size and time
    _info printf "5. Analyzing transfer requirements...\\n"
    local file_count=$(find "${path}" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "${path}" -type d 2>/dev/null | wc -l)
    local total_size_kb=$(du -sk "${path}" 2>/dev/null | cut -f1)
    local total_size_mb=$((total_size_kb / 1024))
    local total_size_gb=$((total_size_mb / 1024))
    
    _info printf "   Files to transfer: %d\\n" "$file_count"
    _info printf "   Directories: %d\\n" "$dir_count"
    if [[ $total_size_gb -gt 0 ]]; then
        _info printf "   Estimated size: %d GB\\n" "$total_size_gb"
    else
        _info printf "   Estimated size: %d MB\\n" "$total_size_mb"
    fi
    
    # Rough time estimate (very approximate)
    local estimated_hours=$((total_size_gb / 10))  # Assume ~10GB/hour
    if [[ $estimated_hours -gt 24 ]]; then
        _warn printf "   Estimated transfer time: >24 hours\\n"
        _warn printf "   Consider breaking this into smaller transfers\\n"
    elif [[ $estimated_hours -gt 1 ]]; then
        _info printf "   Estimated transfer time: ~%d hours\\n" "$estimated_hours"
    else
        _info printf "   Estimated transfer time: <1 hour\\n"
    fi
    
    _info printf "✅ Transfer analysis completed\\n"
    
    _info printf "\\n=== Pre-flight Check Summary ===\\n"
    if [[ $checks_passed -eq 0 ]]; then
        _info printf "✅ All pre-flight checks passed - ready to proceed\\n"
    else
        _exit_1 printf "❌ Some pre-flight checks failed - review issues above\\n"
    fi
    
    return $checks_passed
}