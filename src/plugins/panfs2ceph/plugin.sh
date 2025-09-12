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

    # Note: __validate_bucket_name() is now defined in common.sh

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

# Note: _check_path_permissions(), _check_disk_space(), _validate_rclone_connectivity(), 
# and _run_preflight_checks() are now defined in common.sh

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
    
    # Create the combined copy and verify script
    cat > "${script_prefix}.1_copy_and_verify.slurm" <<EOF
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

echo "✓ Source directory accessibility verified"

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

# Verify the transfer immediately
echo "Starting verification at \$(date)"  
rclone check "${path}" "${remote}:${bucket}/${path_basename}" \\
    --log-file "${script_prefix}.1_verify.rclone.log" \\
    --log-level INFO

echo "Verification completed at \$(date)"

# Generate file lists for comparison
echo "Generating file lists..."
find "${path}" -type f > "${script_prefix}.source_files.txt"
rclone lsf "${remote}:${bucket}/${path_basename}" --recursive > "${script_prefix}.destination_files.txt"

echo "Copy and verification completed at \$(date)"
echo "Files created:"
echo "  Copy log: ${script_prefix}.1_copy.rclone.log"
echo "  Verify log: ${script_prefix}.1_verify.rclone.log"
echo "  Source file list: ${script_prefix}.source_files.txt"
echo "  Destination file list: ${script_prefix}.destination_files.txt"
echo ""
echo "Review verification log for any issues before proceeding with deletion."
EOF

    chmod +x "${script_prefix}.1_copy_and_verify.slurm"
    
    # Create deletion script (renumbered from 3 to 2)
    cat > "${script_prefix}.2_delete.slurm" <<EOF
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

# Verify that copy and verify job completed successfully
echo "Checking if copy and verify job completed successfully..."

# Check if copy log exists
if [[ ! -f "${script_prefix}.1_copy.rclone.log" ]]; then
    echo "ERROR: Copy log not found. Please ensure copy and verify job completed successfully."
    echo "Expected log file: ${script_prefix}.1_copy.rclone.log"
    exit 1
fi

# Check if verification log exists 
if [[ ! -f "${script_prefix}.1_verify.rclone.log" ]]; then
    echo "ERROR: Verification log not found. Please ensure copy and verify job completed successfully."
    echo "Expected log file: ${script_prefix}.1_verify.rclone.log"
    exit 1
fi

# Check verification log for errors
if grep -i "error\|failed\|[1-9][0-9]* differences\|differences found: [1-9]" "${script_prefix}.1_verify.rclone.log" >/dev/null 2>&1; then
    echo "ERROR: Verification log shows errors or differences."
    echo "Please review the verification log before proceeding with deletion:"
    echo "  ${script_prefix}.1_verify.rclone.log"
    exit 1
fi

echo "Copy and verification checks passed. Proceeding with deletion..."

# Perform the deletion with progress and multi-threading
echo "Deleting original data from tier 1 storage..."
echo "Using ${threads} threads for optimal performance"

rclone purge "${path}" \\
    --progress \\
    --multi-thread-streams=${threads} \\
    ${dry_run} \\
    --log-file "${script_prefix}.2_delete.rclone.log" \\
    --log-level INFO \\
    --stats 30s

if [[ \$? -eq 0 ]]; then
    echo "Deletion completed successfully at \$(date)"
    echo "Original data has been removed from: ${path}"
    echo "Data remains safely stored in: ${remote}:${bucket}/${path_basename}"
else
    echo "ERROR: Deletion failed. Please check the log file:"
    echo "  ${script_prefix}.2_delete.rclone.log"
    exit 1
fi

echo "Deletion process completed at \$(date)"
EOF

    chmod +x "${script_prefix}.2_delete.slurm"
    
    # Create restore script (renumbered from 4 to 3)
    cat > "${script_prefix}.3_restore.slurm" <<EOF
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
    --log-file "${script_prefix}.3_restore.rclone.log" \\
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
    echo "  ${script_prefix}.3_restore.rclone.log"
    exit 1
fi

echo "Restore process completed at \$(date)"
EOF

    chmod +x "${script_prefix}.3_restore.slurm"
    
    _info printf "Created SLURM scripts:\\n"
    _info printf "  Copy and Verify: %s\\n" "${script_prefix}.1_copy_and_verify.slurm"
    _info printf "  Delete: %s\\n" "${script_prefix}.2_delete.slurm"
    _info printf "  Restore: %s\\n" "${script_prefix}.3_restore.slurm"
    _info printf "Review and submit scripts in sequence to complete the transfer.\\n"
}