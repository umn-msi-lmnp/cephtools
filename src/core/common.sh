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

# Return an option's value or explain why it is missing.
__get_option_value() {
    local option="${1:-}"
    local value="${2:-}"

    if [[ -z "$value" ]]; then
        _exit_1 printf "%s requires a valid argument. Did you forget to define a variable?\n" "$option"
    elif [[ "$value" == -* ]]; then
        _exit_1 printf "%s requires a valid argument (got '%s' which looks like another option).\n" "$option" "$value"
    fi

    printf "%s\n" "$value"
}

# Read a heredoc into a caller's variable without failing at end of input.
heredoc2var() {
    IFS='\n' read -r -d '' "$1" || true
}

# Accept only positive decimal thread counts without shell arithmetic overflow.
_validate_threads() {
    if [[ ! "${1:-}" =~ ^[0-9]*[1-9][0-9]*$ ]]; then
        _exit_1 printf "Option --threads requires an integer >= 1.\n"
    fi
}

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
  local _target_file="${1}"
  local _saved_dir="$(pwd)"
  local _phys_dir
  local _result

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
  cd "${_saved_dir}"
  _result="${_phys_dir}/${_target_file}"
  printf "%s\n" "${_result}"
}

# _resolve_group_project_root()
#
# Usage:
#   _resolve_group_project_root <group>
#
# Description:
#   Resolve a group to exactly one MSI project root. Valid roots are limited to
#   /projects/{standard,regulated,restricted}/GROUP.
_resolve_group_project_root() {
    local group="${1:-}"
    local root_type=
    local candidate=
    local matches=()

    if [[ -z "$group" ]]; then
        _exit_1 printf "Group is required to resolve project root.\\n"
    fi

    for root_type in standard regulated restricted; do
        candidate="/projects/${root_type}/${group}"
        if [[ -d "$candidate" ]]; then
            matches+=("$candidate")
        fi
    done

    if [[ ${#matches[@]} -eq 1 ]]; then
        printf "%s\\n" "${matches[0]}"
        return 0
    fi

    if [[ ${#matches[@]} -eq 0 ]]; then
        _exit_1 printf "Could not resolve project root for group '%s'. Expected one of /projects/{standard,regulated,restricted}/%s.\\n" "$group" "$group"
    fi

    _exit_1 printf "Ambiguous project root for group '%s': %s\\n" "$group" "${matches[*]}"
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

# _check_rclone_version()
#
# Description:
#   Load the rclone/1.74.4 module for consistent rclone version across all users
#   Uses --force flag to override any sticky modules
_check_rclone_version() {
    _info printf "Loading rclone module for consistent version...\\n"
    
    # Force load the preferred rclone module, overriding any conflicts
    if module load --force rclone/1.74.4 >/dev/null 2>&1; then
        _verb printf "Successfully loaded rclone/1.74.4 module with --force\\n"
    else
        _exit_1 printf "Failed to load rclone/1.74.4 module even with --force flag\\n"
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
  
  if [[ ${#bucket_name} -lt 3 || ${#bucket_name} -gt 63 ]]; then
    _exit_1 printf "Bucket name must be between 3 and 63 characters long: '%s'\\n" "$bucket_name"
  fi

  if [[ "$bucket_name" =~ [^a-zA-Z0-9._-] ]]; then
    _exit_1 printf "Bucket name contains invalid characters. Use only letters, numbers, dots, hyphens, and underscores: '%s'\\n" "$bucket_name"
  fi
  
  printf "%s\\n" "$bucket_name"
}

# __normalize_destination_path()
#
# Usage:
#   __normalize_destination_path <path>
#
# Description:
#   Normalizes a bucket-relative object path without consulting the local
#   filesystem. Empty paths and traversal above the bucket root are rejected.
__normalize_destination_path() {
    local destination_path="${1:-}"
    local component
    local normalized=
    local -a components=()
    local -a normalized_components=()

    if [[ -z "$destination_path" ]]; then
        _exit_1 printf "Destination path cannot be empty.\\n"
    fi

    if [[ "$destination_path" =~ [[:cntrl:]] ]]; then
        _exit_1 printf "Destination path cannot contain control characters.\\n"
    fi

    IFS='/' read -r -a components <<< "$destination_path"
    for component in "${components[@]}"; do
        case "$component" in
        ""|.)
            ;;
        ..)
            if [[ ${#normalized_components[@]} -eq 0 ]]; then
                _exit_1 printf "Destination path cannot traverse above the bucket root: '%s'\\n" "$destination_path"
            fi
            unset 'normalized_components[${#normalized_components[@]}-1]'
            ;;
        *)
            normalized_components+=("$component")
            ;;
        esac
    done

    if [[ ${#normalized_components[@]} -eq 0 ]]; then
        _exit_1 printf "Destination path must identify a location below the bucket root.\\n"
    fi

    normalized="$(IFS=/; printf "%s" "${normalized_components[*]}")"
    printf "%s\\n" "$normalized"
}

# __build_rclone_destination()
#
# Usage:
#   __build_rclone_destination <remote> <bucket> [destination_path]
__build_rclone_destination() {
    local remote="${1:-}"
    local bucket="${2:-}"
    local destination_path="${3:-}"

    if [[ -n "$destination_path" ]]; then
        printf "%s:%s/%s\\n" "$remote" "$bucket" "$destination_path"
    else
        printf "%s:%s\\n" "$remote" "$bucket"
    fi
}

# _warn_if_destination_not_empty()
#
# Usage:
#   _warn_if_destination_not_empty <rclone_destination> <dry_run>
_warn_if_destination_not_empty() {
    local destination="${1:-}"
    local dry_run="${2:-}"
    local listing=

    if [[ -n "$dry_run" ]]; then
        _info printf "Skipping custom destination content check (dry run mode)\\n"
        return 0
    fi

    if ! listing="$(rclone lsf --max-depth 1 "$destination" 2>/dev/null)"; then
        _warn printf "Could not determine whether custom destination is empty: %s\\n" "$destination"
        return 0
    fi

    if [[ -n "$listing" ]]; then
        _warn printf "Custom destination already contains objects: %s\\n" "$destination"
        _warn printf "rclone copy will merge content and overwrite files with matching paths.\\n"
    fi
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
_check_path_permissions() (
    local path="${1:-}"
    local issues_found=0
    local readable_count=0
    local unreadable_count=0
    local total_count=0
    local warning_count=0
    local traversal_failed=0
    local item
    local item_accessible
    local temp_dir
    local inventory
    local issue_log
    
    if [[ -z "$path" ]]; then
        _exit_1 printf "Path cannot be empty for permission check\\n"
    fi
    
    _info printf "Checking file permissions for: %s\\n" "$path"
    
    # Check if path exists and is accessible
    if [[ ! -e "$path" ]]; then
        _warn printf "Path does not exist: %s\\n" "$path"
        return 1
    fi

    # Comprehensive file permission scan
    _info printf "Scanning file permissions (this may take a while for large directories)...\\n"

    temp_dir="$(mktemp -d)"
    inventory="${temp_dir}/inventory"
    issue_log="${temp_dir}/issues"
    : > "$issue_log"
    trap 'rm -rf "$temp_dir"' EXIT

    if ! find "$path" \( -type f -o -type d \) -print0 > "$inventory"; then
        traversal_failed=1
        issues_found=1
        _warn printf "Could not completely traverse path: %s\\n" "$path"
    fi

    while IFS= read -r -d '' item; do
        total_count=$((total_count + 1))
        item_accessible=1

        if [[ -d "$item" ]]; then
            if [[ ! -r "$item" || ! -x "$item" ]] || ! ls -A -- "$item" >/dev/null 2>&1; then
                item_accessible=0
            fi
        elif [[ ! -r "$item" ]]; then
            item_accessible=0
        fi

        if [[ $item_accessible -eq 1 ]]; then
            readable_count=$((readable_count + 1))
        else
            unreadable_count=$((unreadable_count + 1))
            issues_found=1
            printf '%s\0' "$item" >> "$issue_log"
            if [[ $warning_count -lt 5 ]]; then
                _warn printf "Cannot read, search, or list: %s\\n" "$item"
                warning_count=$((warning_count + 1))
            fi
        fi
    done < "$inventory"
    
    # Report results
    _info printf "Permission scan complete:\\n"
    _info printf "  Total items: %d\\n" "$total_count"
    _info printf "  Readable: %d\\n" "$readable_count"
    _info printf "  Unreadable: %d\\n" "$unreadable_count"
    if [[ $traversal_failed -eq 1 ]]; then
        _warn printf "  Traversal complete: no\\n"
    fi
    
    if [[ $issues_found -eq 1 ]]; then
        _warn printf "Found %d inaccessible files/directories\\n" "$unreadable_count"
        
        # Show summary of unreadable items
        if [[ -s "$issue_log" ]]; then
            local log_count=0
            _warn printf "Unreadable items logged. First 10:\\n"
            while IFS= read -r -d '' item; do
                log_count=$((log_count + 1))
                if [[ $log_count -le 10 ]]; then
                    _warn printf "  %s\\n" "$item"
                fi
            done < "$issue_log"

            if [[ $log_count -gt 10 ]]; then
                _warn printf "  ... and %d more\\n" $((log_count - 10))
            fi
        fi
        
        _warn printf "Permission issues detected. These files will not be transferred.\\n"
    else
        _info printf "All files and directories are accessible\\n"
    fi

    return $issues_found
)

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

# _check_bucket_write_permissions()
#
# Usage:
#   _check_bucket_write_permissions <bucket> <dry_run>
#
# Description:
#   Validates that the user has write permissions to the specified S3/Ceph bucket
#   without actually writing files. Uses S3 bucket policy and ACL inspection.
#   Returns 0 if write permissions are confirmed, 1 if issues are found.
_check_bucket_write_permissions() {
    local bucket="${1:-}"
    local dry_run="${2:-}"
    
    if [[ -z "$bucket" ]]; then
        _exit_1 printf "Bucket name cannot be empty for permission check\\n"
        return 1
    fi
    
    _info printf "Checking bucket write permissions for: %s\\n" "$bucket"
    
    # Skip actual checks in dry run mode to avoid credential issues
    if [[ -n "${dry_run}" ]]; then
        _info printf "Skipping bucket write permission check (dry run mode)\\n"
        return 0
    fi
    
    # Method 1: Check bucket policy using s3cmd
    local bucket_policy_check=0
    _verb printf "Checking bucket policy...\\n"
    
    # Get bucket policy information
    local policy_output
    if policy_output=$(s3cmd info "s3://${bucket}" 2>/dev/null); then
        _verb printf "Bucket policy information retrieved\\n"
        
        # Check if bucket policy allows write operations
        if echo "$policy_output" | grep -q "Policy:"; then
            _verb printf "Bucket has a policy set\\n"
            
            # Get the actual policy JSON if possible
            local policy_json
            if policy_json=$(s3cmd getpolicy "s3://${bucket}" 2>/dev/null); then
                # Check for write permissions in policy
                if echo "$policy_json" | grep -qE '"s3:\*"|"s3:PutObject"|"s3:DeleteObject"'; then
                    _info printf "✓ Bucket policy allows write operations\\n"
                    bucket_policy_check=1
                else
                    _warn printf "Bucket policy may not allow write operations\\n"
                fi
            else
                _verb printf "Could not retrieve bucket policy details\\n"
            fi
        else
            _verb printf "No explicit bucket policy found\\n"
        fi
    else
        _warn printf "Could not retrieve bucket information\\n"
    fi
    
    # Method 2: Test with a small metadata operation (safest approach)
    local metadata_check=0
    _verb printf "Testing bucket access with metadata operations...\\n"
    
    # Try to list bucket contents (requires ListBucket permission)
    if s3cmd ls "s3://${bucket}" >/dev/null 2>&1; then
        _verb printf "✓ Can list bucket contents\\n"
        metadata_check=1
        
        # Method 3: Check if we can upload/delete a tiny test marker
        # This is more definitive but we want to avoid actual file operations
        local test_key="cephtools-permission-test-$(date +%s)-$$"
        local test_content="test"
        
        # Use s3cmd's ability to upload from stdin
        _verb printf "Testing write permissions with temporary test object...\\n"
        if echo "$test_content" | s3cmd put - "s3://${bucket}/${test_key}" >/dev/null 2>&1; then
            _verb printf "✓ Successfully uploaded test object\\n"
            
            # Clean up immediately
            if s3cmd del "s3://${bucket}/${test_key}" >/dev/null 2>&1; then
                _verb printf "✓ Successfully deleted test object\\n"
                _info printf "✓ Bucket write permissions confirmed\\n"
                return 0
            else
                _warn printf "Could delete test object, but write permission confirmed\\n"
                return 0
            fi
        else
            _warn printf "Cannot write to bucket: ${bucket}\\n"
        fi
    else
        _warn printf "Cannot list bucket contents: ${bucket}\\n"
    fi
    
    # Evaluate results - for write operations, we must have confirmed write access
    if [[ $bucket_policy_check -eq 1 || $metadata_check -eq 1 ]]; then
        _exit_1 printf "Cannot confirm bucket WRITE permissions for: %s\\nBucket appears accessible but write permissions could not be verified.\\nThis indicates read-only access or insufficient permissions.\\nRequired actions:\\n  - Check bucket policy: s3cmd info s3://%s\\n  - Verify group membership and bucket write policies\\n  - Use 'cephtools bucketpolicy --policy GROUP_READ_WRITE' to grant write access\\n" "$bucket" "$bucket"
    else
        _exit_1 printf "Cannot access bucket for writing: %s\\nPossible issues:\\n  - Bucket does not exist (use 'cephtools bucketpolicy --make_bucket')\\n  - No access permissions (check bucket policy)\\n  - S3 credentials not properly configured\\nRequired: Bucket must exist and allow write operations for this transfer.\\n" "$bucket"
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
    
    # 4.5. Bucket write permissions check
    _info printf "4.5. Checking bucket write permissions...\\n"
    if ! _check_bucket_write_permissions "${bucket}" "${dry_run}"; then
        if [[ -z "${dry_run}" ]]; then
            _exit_1 printf "❌ Bucket write permission check failed\\n"
            checks_passed=1
        else
            _warn printf "⚠️  Bucket write permission issues detected, but continuing with dry run\\n"
        fi
    else
        _info printf "✅ Bucket write permission check passed\\n"
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
