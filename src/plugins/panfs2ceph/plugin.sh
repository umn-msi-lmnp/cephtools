#!/usr/bin/env bash
###############################################################################
# panfs2ceph Plugin for cephtools
# Archiving tool to copy a single directory from tier 1 (panfs) storage to tier 2 (ceph).
###############################################################################

# Plugin metadata
PLUGIN_NAME="panfs2ceph"

PLUGIN_DESCRIPTION="Archive tool to copy directories from panfs to ceph"

###############################################################################
# Plugin Interface Functions
###############################################################################

plugin_describe() {
cat <<HEREDOC
---------------------------------------------------------------------
Usage:
    ${_ME} panfs2ceph [options] --bucket <BUCKET> --path <DIR_PATH>

Options:
    -r|--remote <STRING>    [Optional] Rclone remote name. (use "rclone listremotes" for available
                            remotes). Rclone remotes must be set up using "rclone init"
                            and can be viewed at: ~/.config/rclone/rclone.conf. This option
                            is not required. If you do not specify --remote, the tool will 
                            automatically identify your MSI ceph keys and set the remote. 
                            This option was left here for backward compatibility.
                            
    -b|--bucket <STRING>    Name of the ceph bucket that data should be used for the 
                            transfer.
    
    -p|--path <STRING>      Absolute or relative path to the directory that should be 
                            transfered.
                            
    -l|--log_dir <STRING>   Absolute or relative path to the directory where log files 
                            are saved. [Default: "<path>___panfs2ceph_archive_<date_time>"]
    
    -d|--dry_run            Dry run option will be applied to rclone commands. Nothing 
                            transfered or deleted when scripts run.
    
     -e|--delete_empty_dirs  Do NOT transfer empty dirs from panfs to ceph. [Default is to 
                             transfer empty dirs using rclone's native directory handling 
                             with --create-empty-src-dirs --s3-directory-markers flags.
                             Setting this flag will omit these flags.]
                            
    -t|--threads <INT>      Threads to use for uploading with rclone. [Default = 16].
    
    -v|--verbose            Verbose mode (print additional info).

Description:
  Archiving tool to copy a single directory from tier 1 (panfs) storage to tier 2 (ceph).
  
Help (print this screen):
    ${_ME} help panfs2ceph

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
GitHub: https://github.umn.edu/lmnp/cephtools

Version: $VERSION_SHORT
---------------------------------------------------------------------
HEREDOC
}

plugin_main() {
    # Show help if no arguments provided
    if [[ $# -eq 0 ]]; then
        plugin_describe
        return 0
    fi

    # Parse Options ###############################################################

    # Initialize program option variables.
    local _bucket=
    local _remote="myremote"
    local _path=
    local _log_dir=
    local _dry_run=
    local _verbose=0
    local _delete_empty_dirs=0
    local _threads="16"

    # __get_option_value()
    #
    # Usage:
    #   __get_option_value <option> <value>
    #
    # Description:
    #  Given a flag (e.g., -e | --example) return the value or exit 1 if value
    #  is blank or appears to be another option.
    __get_option_value() {
      local __arg="${1:-}"
      local __val="${2:-}"
      
      if [[ -n "${__val:-}" ]] && [[ ! "${__val:-}" =~ ^- ]]
      then
        printf "%s\\n" "${__val}"
      else
        _exit_1 printf "%s requires a valid argument.\\n" "${__arg}"
      fi
    }

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

    # For flags (i.e. no corresponding value), do not shift inside the case testing
    # statement. For options with required value, shift inside case testing statement, 
    # so the loop moves twice. 
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -d|--dry_run)
            _dry_run="--dry-run"
            ;;
        -v|--verbose)
            _verbose=1
            ;;
        -e|--delete_empty_dirs)
            _delete_empty_dirs=1
            ;;
        -b|--bucket)
            _bucket="$(__validate_bucket_name "$(__get_option_value "${__arg}" "${__val:-}")")"
            shift
            ;;
        -r|--remote)
            _remote="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -p|--path)
            _path="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -l|--log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -t|--threads)
            _threads="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        --endopts)
            # Terminate option parsing.
            break
            ;;
        -*)
            _exit_1 printf "Unexpected option: %s\\n" "${__arg}"
            ;;
        *)
            plugin_describe
            _exit_1 printf "Unexpected positional arg: %s\\n" "${__arg}"
            ;;
        esac

        shift
    done

    # Set verbose mode if requested
    if [[ ${_verbose} -eq 1 ]]; then
        _USE_VERBOSE=1
    fi

    # ---------------------------------------------------------------------
    # Setup rclone credentials if using default remote
    # ---------------------------------------------------------------------
    
    if [[ "$_remote" == "myremote" ]]; then
        if command -v s3info >/dev/null 2>&1; then
            export RCLONE_CONFIG_MYREMOTE_TYPE=s3
            export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE
            RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID="$(s3info --keys | awk '{print $1}')"
            RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY="$(s3info --keys | awk '{print $2}')"
            export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY
            export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu
            export RCLONE_CONFIG_MYREMOTE_ACL=private
            export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph
        else
            _exit_1 printf "s3info failed\\n"
        fi
    fi

    # ---------------------------------------------------------------------
    # Check and print input options
    # ---------------------------------------------------------------------
    
    if [[ -z "${_bucket:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--bucket' is required.\\n"
    fi

    if [[ -z "${_path:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--path' is required.\\n"
    fi

    # Convert relative path to absolute path
    _path="$(cd "${_path}" && pwd)" || _exit_1 printf "Path '%s' does not exist or is not accessible.\\n" "${_path}"
    
    # Set default log directory if not provided
    if [[ -z "${_log_dir:-}" ]]; then
        _log_dir="${_path}___panfs2ceph_archive_$(date +%Y%m%d_%H%M%S)"
    fi

    # Create log directory
    mkdir -p "${_log_dir}" || _exit_1 printf "Failed to create log directory: %s\\n" "${_log_dir}"

    _verb printf "Using options:\\n"
    _verb printf "  Bucket: %s\\n" "${_bucket}"
    _verb printf "  Remote: %s\\n" "${_remote}"
    _verb printf "  Path: %s\\n" "${_path}"
    _verb printf "  Log Directory: %s\\n" "${_log_dir}"
    _verb printf "  Threads: %s\\n" "${_threads}"
    _verb printf "  Dry Run: %s\\n" "${_dry_run:-disabled}"
    _verb printf "  Delete Empty Dirs: %s\\n" "$([[ ${_delete_empty_dirs} -eq 1 ]] && echo "enabled" || echo "disabled")"

    # ---------------------------------------------------------------------
    # Execute the main workflow
    # ---------------------------------------------------------------------
    
    _info printf "Starting panfs2ceph transfer preparation\\n"
    _info printf "Source: %s\\n" "${_path}"
    _info printf "Destination: %s:%s\\n" "${_remote}" "${_bucket}"
    
    # Run comprehensive pre-flight checks
    if ! _run_preflight_checks "${_path}" "${_remote}" "${_bucket}" "${_log_dir}" "${_dry_run}"; then
        if [[ -z "${_dry_run}" ]]; then
            _exit_1 printf "Pre-flight checks failed. Use --dry_run to proceed anyway, or fix issues first.\\n"
            return 1
        else
            _warn printf "Pre-flight checks had issues, but continuing with dry run.\\n"
        fi
    fi
    
    # Create the transfer scripts
    _create_transfer_scripts "${_bucket}" "${_remote}" "${_path}" "${_log_dir}" "${_dry_run}" "${_delete_empty_dirs}" "${_threads}"
    
    _info printf "Transfer scripts created in: %s\\n" "${_log_dir}"
    _info printf "Review and submit the generated SLURM scripts to complete the transfer.\\n"
}

###############################################################################
# Helper Functions
###############################################################################

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
        _exit_1 printf "Path does not exist: %s\\n" "$path"
        return 1
    fi
    
    if [[ ! -r "$path" ]]; then
        _exit_1 printf "Cannot read path: %s\\n" "$path"
        return 1
    fi
    
    # Check if we can list directory contents
    if [[ -d "$path" ]]; then
        if ! ls "$path" >/dev/null 2>&1; then
            _exit_1 printf "Cannot list directory contents: %s\\n" "$path"
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

# _run_preflight_checks()
#
# Usage:
#   _run_preflight_checks <path> <remote> <bucket> <log_dir> <dry_run>
#
# Description:
#   Runs all pre-flight checks and returns 0 if everything looks good
_run_preflight_checks() {
    local path="${1:-}"
    local remote="${2:-}"
    local bucket="${3:-}"
    local log_dir="${4:-}"
    local dry_run="${5:-}"
    local checks_passed=0
    
    _info printf "\\n=== Pre-flight Checks ===\\n"
    
    # 1. Path accessibility and permissions
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

_create_transfer_scripts() {
    local bucket="${1}"
    local remote="${2}"
    local path="${3}"
    local log_dir="${4}"
    local dry_run="${5}"
    local delete_empty_dirs="${6}"
    local threads="${7}"
    
    local path_basename="$(basename "${path}")"
    local script_prefix="${log_dir}/${path_basename}"
    
    # Create the main transfer script
    cat > "${script_prefix}.1_copy.slurm" <<EOF
#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rclone/1.71.0-r1

# Set up credentials
$(if command -v s3info >/dev/null 2>&1; then
    echo "export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')"
    echo "export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')"
    echo "export RCLONE_CONFIG_MYREMOTE_TYPE=\"s3\""
    echo "export RCLONE_CONFIG_MYREMOTE_PROVIDER=\"Ceph\""
    echo "export RCLONE_CONFIG_MYREMOTE_ENDPOINT=\"https://s3.msi.umn.edu\""
fi)

# Pre-transfer validation
echo "Performing pre-transfer validation..."

# Quick permission check
echo "Checking source directory accessibility..."
if [[ ! -r "${path}" ]]; then
    echo "ERROR: Cannot read source directory: ${path}"
    exit 1
fi

# Check for obvious permission issues
echo "Checking for files with permission issues..."
unreadable_count=\$(find "${path}" ! -readable 2>/dev/null | wc -l)
if [[ \$unreadable_count -gt 0 ]]; then
    echo "WARNING: Found \$unreadable_count files/directories that may not be readable"
    echo "These files may not be transferred successfully"
fi

# Perform the transfer
echo "Starting transfer at \$(date)"
echo "Source: ${path}"
echo "Destination: ${remote}:${bucket}/${path_basename}"

$(if [[ ${delete_empty_dirs} -eq 0 ]]; then
    echo "echo \"Using rclone native empty directory handling...\""
    echo "rclone copy \"${path}\" \"${remote}:${bucket}/${path_basename}\" \\"
    echo "    --transfers ${threads} \\"
    echo "    --progress \\"
    echo "    --stats 30s \\"
    echo "    ${dry_run} \\"
    echo "    --create-empty-src-dirs \\"
    echo "    --s3-directory-markers \\"
    echo "    --log-file \"${script_prefix}.1_copy.rclone.log\" \\"
    echo "    --log-level INFO"
else
    echo "echo \"Skipping empty directories...\""
    echo "rclone copy \"${path}\" \"${remote}:${bucket}/${path_basename}\" \\"
    echo "    --transfers ${threads} \\"
    echo "    --progress \\"
    echo "    --stats 30s \\"
    echo "    ${dry_run} \\"
    echo "    --log-file \"${script_prefix}.1_copy.rclone.log\" \\"
    echo "    --log-level INFO"
fi)

echo "Transfer completed at \$(date)"

# Generate file lists for verification
echo "Generating file lists..."
find "${path}" -type f > "${script_prefix}.source_files.txt"
rclone lsf "${remote}:${bucket}/${path_basename}" --recursive > "${script_prefix}.destination_files.txt"

echo "File lists created:"
echo "  Source: ${script_prefix}.source_files.txt"
echo "  Destination: ${script_prefix}.destination_files.txt"
EOF

    chmod +x "${script_prefix}.1_copy.slurm"
    
    # Create verification script
    cat > "${script_prefix}.2_verify.slurm" <<EOF
#!/bin/bash
#SBATCH --time=4:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rclone/1.71.0-r1

# Set up credentials
$(if command -v s3info >/dev/null 2>&1; then
    echo "export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')"
    echo "export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')"
    echo "export RCLONE_CONFIG_MYREMOTE_TYPE=\"s3\""
    echo "export RCLONE_CONFIG_MYREMOTE_PROVIDER=\"Ceph\""
    echo "export RCLONE_CONFIG_MYREMOTE_ENDPOINT=\"https://s3.msi.umn.edu\""
fi)

# Verify the transfer
echo "Starting verification at \$(date)"
rclone check "${path}" "${remote}:${bucket}/${path_basename}" \\
    --log-file "${script_prefix}.2_verify.rclone.log" \\
    --log-level INFO

echo "Verification completed at \$(date)"
EOF

    chmod +x "${script_prefix}.2_verify.slurm"
    
    # Create deletion script
    cat > "${script_prefix}.3_delete.slurm" <<EOF
#!/bin/bash
#SBATCH --time=8:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=16gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rclone/1.71.0-r1

# Set up credentials
$(if command -v s3info >/dev/null 2>&1; then
    echo "export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')"
    echo "export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')"
    echo "export RCLONE_CONFIG_MYREMOTE_TYPE=\"s3\""
    echo "export RCLONE_CONFIG_MYREMOTE_PROVIDER=\"Ceph\""
    echo "export RCLONE_CONFIG_MYREMOTE_ENDPOINT=\"https://s3.msi.umn.edu\""
fi)

# Safety checks before deletion
echo "Starting deletion process at \$(date)"
echo "WARNING: This will permanently delete the original data from tier 1 storage!"
echo "Source directory to delete: ${path}"

# Verify that copy and verify jobs completed successfully
echo "Checking if previous jobs completed successfully..."

# Check if verification log exists and shows success
if [[ ! -f "${script_prefix}.2_verify.rclone.log" ]]; then
    echo "ERROR: Verification log not found. Please ensure copy and verify jobs completed successfully."
    echo "Expected log file: ${script_prefix}.2_verify.rclone.log"
    exit 1
fi

# Check verification log for errors
if grep -i "error\|failed\|[1-9][0-9]* differences\|differences found: [1-9]" "${script_prefix}.2_verify.rclone.log" >/dev/null 2>&1; then
    echo "ERROR: Verification log shows errors or differences."
    echo "Please review the verification log before proceeding with deletion:"
    echo "  ${script_prefix}.2_verify.rclone.log"
    exit 1
fi

echo "Verification checks passed. Proceeding with deletion..."

# Perform the deletion with progress and multi-threading
echo "Deleting original data from tier 1 storage..."
echo "Using ${threads} threads for optimal performance"

rclone purge "${path}" \\
    --progress \\
    --multi-thread-streams=${threads} \\
    ${dry_run} \\
    --log-file "${script_prefix}.3_delete.rclone.log" \\
    --log-level INFO \\
    --stats 30s

if [[ \$? -eq 0 ]]; then
    echo "Deletion completed successfully at \$(date)"
    echo "Original data has been removed from: ${path}"
    echo "Data remains safely stored in: ${remote}:${bucket}/${path_basename}"
else
    echo "ERROR: Deletion failed. Please check the log file:"
    echo "  ${script_prefix}.3_delete.rclone.log"
    exit 1
fi

echo "Deletion process completed at \$(date)"
EOF

    chmod +x "${script_prefix}.3_delete.slurm"
    
    # Create restore script
    cat > "${script_prefix}.4_restore.slurm" <<EOF
#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rclone/1.71.0-r1

# Set up credentials
$(if command -v s3info >/dev/null 2>&1; then
    echo "export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=\$(s3info --keys | awk '{print \$1}')"
    echo "export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=\$(s3info --keys | awk '{print \$2}')"
    echo "export RCLONE_CONFIG_MYREMOTE_TYPE=\"s3\""
    echo "export RCLONE_CONFIG_MYREMOTE_PROVIDER=\"Ceph\""
    echo "export RCLONE_CONFIG_MYREMOTE_ENDPOINT=\"https://s3.msi.umn.edu\""
fi)

# Restore process
echo "Starting restore process at \$(date)"
echo "Source: ${remote}:${bucket}/${path_basename}"
echo "Destination: ${path}"

# Safety checks
if [[ -e "${path}" ]]; then
    echo "WARNING: Destination path already exists: ${path}"
    echo "This restore operation will overwrite existing files with the same names."
    echo "Continuing in 10 seconds... (Press Ctrl+C to abort)"
    sleep 10
fi

# Verify source exists in tier 2 storage
echo "Verifying source data exists in tier 2 storage..."
if ! rclone lsd "${remote}:${bucket}/${path_basename}" >/dev/null 2>&1; then
    echo "ERROR: Source data not found in tier 2 storage"
    echo "Expected location: ${remote}:${bucket}/${path_basename}"
    echo "Please verify the bucket and path are correct"
    exit 1
fi

echo "Source data confirmed in tier 2 storage"

# Create parent directory if it doesn't exist
parent_dir="\$(dirname "${path}")"
if [[ ! -d "\$parent_dir" ]]; then
    echo "Creating parent directory: \$parent_dir"
    mkdir -p "\$parent_dir" || {
        echo "ERROR: Failed to create parent directory: \$parent_dir"
        exit 1
    }
fi

# Perform the restore
echo "Starting restore from tier 2 back to tier 1..."
rclone copy "${remote}:${bucket}/${path_basename}" "${path}" \\
    --transfers ${threads} \\
    --progress \\
    --stats 30s \\
    ${dry_run} \\
    --log-file "${script_prefix}.4_restore.rclone.log" \\
    --log-level INFO

if [[ \$? -eq 0 ]]; then
    echo "Restore completed successfully at \$(date)"
    echo "Data has been restored to: ${path}"
    
    # Generate file list for verification
    echo "Generating restored file list..."
    find "${path}" -type f > "${script_prefix}.restored_files.txt"
    echo "Restored file list: ${script_prefix}.restored_files.txt"
else
    echo "ERROR: Restore failed. Please check the log file:"
    echo "  ${script_prefix}.4_restore.rclone.log"
    exit 1
fi

echo "Restore process completed at \$(date)"
EOF

    chmod +x "${script_prefix}.4_restore.slurm"
    
    _info printf "Created SLURM scripts:\\n"
    _info printf "  Transfer: %s\\n" "${script_prefix}.1_copy.slurm"
    _info printf "  Verify: %s\\n" "${script_prefix}.2_verify.slurm"
    _info printf "  Delete: %s\\n" "${script_prefix}.3_delete.slurm"
    _info printf "  Restore: %s\\n" "${script_prefix}.4_restore.slurm"
}