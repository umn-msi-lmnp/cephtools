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
                             The restore script also uses --create-empty-src-dirs to 
                             recreate empty directories. Setting this flag will omit these flags.]
                            
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
    # Note: Don't exit early for no arguments - let validation handle required params

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
        # In test environment, use TEST_OUTPUT_DIR as base
        if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
            local path_basename="$(basename "${_path}")"
            _log_dir="${TEST_OUTPUT_DIR}/${path_basename}___panfs2ceph_archive_$(date +%Y%m%d_%H%M%S)_$(date +"%N" | cut -c1-6)"
        else
            _log_dir="${_path}___panfs2ceph_archive_$(date +%Y%m%d_%H%M%S)_$(date +"%N" | cut -c1-6)"
        fi
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
    
    #######################################################################
    # Print instructions to terminal
    #######################################################################

    # Use a temp function to create multi-line string without affecting exit code
    # https://stackoverflow.com/a/8088167/2367748
    heredoc2var(){ IFS='\n' read -r -d '' ${1} || true; }
    
    local instructions_message
    heredoc2var instructions_message << HEREDOC

---------------------------------------------------------------------
cephtools panfs2ceph summary


Options used:
dry_run=${_dry_run}
delete_empty_dirs=${_delete_empty_dirs}
remote=${_remote}
bucket=${_bucket}
threads=${_threads}


Archive dir: 
${_path}


Archive dir transfer scripts:
${_log_dir}


Archive transfer files created -- but you're not done yet!
Next steps:
1. Move into transfer dir: cd ${_log_dir}
2. Review the generated SLURM scripts for details.
3. Launch the copy and verify jobfile: sbatch $(basename "${_path}").1_copy_and_verify.slurm
4. After successful copy and verify, launch the delete jobfile: sbatch $(basename "${_path}").2_delete.slurm
5. After the data has been deleted from panfs -- and you need it back in the same location, launch the restore jobfile: sbatch $(basename "${_path}").3_restore.slurm




VERSION: ${VERSION_SHORT}
QUESTIONS: lmp-help@msi.umn.edu
REPO: https://github.umn.edu/lmnp/cephtools
---------------------------------------------------------------------
HEREDOC

    echo "$instructions_message"
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
#SBATCH --partition=msismall
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# ------------------------------------------------------------------------------
# Bash safe mode
# ------------------------------------------------------------------------------

# --- Safe defaults ---
set -o errexit   # Exit immediately if a command fails
set -o nounset   # Treat unset variables as an error
set -o pipefail  # Fail if any part of a pipeline fails
set -o errtrace  # Inherit ERR traps in functions/subshells

# Uncomment if you use DEBUG/RETURN traps (rare in production)
# set -o functrace  

# Error handler
error_handler() {
    local exit_code=\$?
    local cmd="\${BASH_COMMAND}"
    local line="\${BASH_LINENO[0]}"
    local src="\${BASH_SOURCE[1]:-main script}"

    >&2 echo "ERROR [\$(date)]"
    >&2 echo "  File: \$src"
    >&2 echo "  Line: \$line"
    >&2 echo "  Command: \$cmd"
    >&2 echo "  Exit code: \$exit_code"

    exit "\$exit_code"
}

# Exit handler (always runs on exit)
on_exit() {
    local exit_code=\$?
    echo "Exiting script (code \$exit_code) [\$(date)]"
    # Add temp file cleanup or resource release here
}

# Signal handlers
on_interrupt() {
    echo "Interrupt signal (SIGINT) received. Exiting."
    exit 130   # 128 + SIGINT(2)
}

on_terminate() {
    echo "Terminate signal (SIGTERM) received. Exiting."
    exit 143   # 128 + SIGTERM(15)
}

on_quit() {
    echo "Quit signal (SIGQUIT) received. Exiting."
    exit 131   # 128 + SIGQUIT(3)
}

# Trap setup
trap error_handler ERR # calls error_handler when a command fails.
trap on_exit EXIT # Runs no matter how the script ends.
trap on_interrupt INT # handles Ctrl-C.
trap on_terminate TERM # handles kill or system shutdown signals
trap on_quit QUIT # handles Ctrl-\ (prevents core dump).

# Load required modules
# Force load consistent rclone version, overriding any sticky modules
if ! module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
    echo "Error: Failed to load rclone/1.71.0-r1 module even with --force flag"
    exit 1
else
    echo "Successfully loaded rclone/1.71.0-r1 module"
fi
echo "Using rclone: $(command -v rclone)"
echo "Version: $(rclone --version 2>/dev/null | head -1 || echo 'version unknown')"

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
echo "Destination: ${remote}:${bucket}/${path#/}"

$(if [[ ${delete_empty_dirs} -eq 0 ]]; then
    echo "echo \"Using rclone native empty directory handling...\""
    echo "rclone copy \"${path}\" \"${remote}:${bucket}/${path#/}\" \\"
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
    echo "rclone copy \"${path}\" \"${remote}:${bucket}/${path#/}\" \\"
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
rclone check "${path}" "${remote}:${bucket}/${path#/}" \\
    --log-file "${script_prefix}.1_verify.rclone.log" \\
    --progress \\
    --log-level DEBUG \\
    --transfers ${threads} \\
    --checkers ${threads} \\
    --retries 5 \\
    --low-level-retries 20 \\
    --one-way \\
    --differ "${script_prefix}.1_verify.rclone.differ.txt" \\
    --missing-on-dst "${script_prefix}.1_verify.rclone.missing-on-tier2.txt" \\
    --error "${script_prefix}.1_verify.rclone.error.txt"

echo "Verification completed at \$(date)"

# Create success marker file to indicate successful completion
echo "Creating success marker file..."
echo "Copy and verify operations completed successfully at \$(date)" > "${script_prefix}.copy_and_verify_SUCCESS.txt"
echo "Success marker file created. Ready to proceed with deletion script."
EOF

    chmod +x "${script_prefix}.1_copy_and_verify.slurm"
    
    # Create deletion script (renumbered from 3 to 2)
    cat > "${script_prefix}.2_delete.slurm" <<EOF
#!/bin/bash
#SBATCH --time=8:00:00
#SBATCH --partition=msismall
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=16gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# ------------------------------------------------------------------------------
# Bash safe mode
# ------------------------------------------------------------------------------

# --- Safe defaults ---
set -o errexit   # Exit immediately if a command fails
set -o nounset   # Treat unset variables as an error
set -o pipefail  # Fail if any part of a pipeline fails
set -o errtrace  # Inherit ERR traps in functions/subshells

# Uncomment if you use DEBUG/RETURN traps (rare in production)
# set -o functrace  

# Error handler
error_handler() {
    local exit_code=\$?
    local cmd="\${BASH_COMMAND}"
    local line="\${BASH_LINENO[0]}"
    local src="\${BASH_SOURCE[1]:-main script}"

    >&2 echo "ERROR [\$(date)]"
    >&2 echo "  File: \$src"
    >&2 echo "  Line: \$line"
    >&2 echo "  Command: \$cmd"
    >&2 echo "  Exit code: \$exit_code"

    exit "\$exit_code"
}

# Exit handler (always runs on exit)
on_exit() {
    local exit_code=\$?
    echo "Exiting script (code \$exit_code) [\$(date)]"
    # Add temp file cleanup or resource release here
}

# Signal handlers
on_interrupt() {
    echo "Interrupt signal (SIGINT) received. Exiting."
    exit 130   # 128 + SIGINT(2)
}

on_terminate() {
    echo "Terminate signal (SIGTERM) received. Exiting."
    exit 143   # 128 + SIGTERM(15)
}

on_quit() {
    echo "Quit signal (SIGQUIT) received. Exiting."
    exit 131   # 128 + SIGQUIT(3)
}

# Trap setup
trap error_handler ERR # calls error_handler when a command fails.
trap on_exit EXIT # Runs no matter how the script ends.
trap on_interrupt INT # handles Ctrl-C.
trap on_terminate TERM # handles kill or system shutdown signals
trap on_quit QUIT # handles Ctrl-\ (prevents core dump).

# Load required modules
# Force load consistent rclone version, overriding any sticky modules
if ! module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
    echo "Error: Failed to load rclone/1.71.0-r1 module even with --force flag"
    exit 1
else
    echo "Successfully loaded rclone/1.71.0-r1 module"
fi
echo "Using rclone: $(command -v rclone)"
echo "Version: $(rclone --version 2>/dev/null | head -1 || echo 'version unknown')"

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

# Check for success marker file
if [[ ! -f "${script_prefix}.copy_and_verify_SUCCESS.txt" ]]; then
    echo "ERROR: Success marker file not found. Please ensure copy and verify job completed successfully."
    echo "Expected marker file: ${script_prefix}.copy_and_verify_SUCCESS.txt"
    echo "This file is created only when both copy and verify operations complete with exit code 0."
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
    echo "Data remains safely stored in: ${remote}:${bucket}/${path#/}"
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
#SBATCH --partition=msismall
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=32gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# ------------------------------------------------------------------------------
# Bash safe mode
# ------------------------------------------------------------------------------

# --- Safe defaults ---
set -o errexit   # Exit immediately if a command fails
set -o nounset   # Treat unset variables as an error
set -o pipefail  # Fail if any part of a pipeline fails
set -o errtrace  # Inherit ERR traps in functions/subshells

# Uncomment if you use DEBUG/RETURN traps (rare in production)
# set -o functrace  

# Error handler
error_handler() {
    local exit_code=\$?
    local cmd="\${BASH_COMMAND}"
    local line="\${BASH_LINENO[0]}"
    local src="\${BASH_SOURCE[1]:-main script}"

    >&2 echo "ERROR [\$(date)]"
    >&2 echo "  File: \$src"
    >&2 echo "  Line: \$line"
    >&2 echo "  Command: \$cmd"
    >&2 echo "  Exit code: \$exit_code"

    exit "\$exit_code"
}

# Exit handler (always runs on exit)
on_exit() {
    local exit_code=\$?
    echo "Exiting script (code \$exit_code) [\$(date)]"
    # Add temp file cleanup or resource release here
}

# Signal handlers
on_interrupt() {
    echo "Interrupt signal (SIGINT) received. Exiting."
    exit 130   # 128 + SIGINT(2)
}

on_terminate() {
    echo "Terminate signal (SIGTERM) received. Exiting."
    exit 143   # 128 + SIGTERM(15)
}

on_quit() {
    echo "Quit signal (SIGQUIT) received. Exiting."
    exit 131   # 128 + SIGQUIT(3)
}

# Trap setup
trap error_handler ERR # calls error_handler when a command fails.
trap on_exit EXIT # Runs no matter how the script ends.
trap on_interrupt INT # handles Ctrl-C.
trap on_terminate TERM # handles kill or system shutdown signals
trap on_quit QUIT # handles Ctrl-\ (prevents core dump).

# Load required modules
# Force load consistent rclone version, overriding any sticky modules
if ! module load --force rclone/1.71.0-r1 >/dev/null 2>&1; then
    echo "Error: Failed to load rclone/1.71.0-r1 module even with --force flag"
    exit 1
else
    echo "Successfully loaded rclone/1.71.0-r1 module"
fi
echo "Using rclone: $(command -v rclone)"
echo "Version: $(rclone --version 2>/dev/null | head -1 || echo 'version unknown')"

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
echo "Source: ${remote}:${bucket}/${path#/}"
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
if ! rclone lsd "${remote}:${bucket}/${path#/}" >/dev/null 2>&1; then
    echo "ERROR: Source data not found in tier 2 storage"
    echo "Expected location: ${remote}:${bucket}/${path#/}"
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
rclone copy "${remote}:${bucket}/${path#/}" "${path}" \\
    --transfers ${threads} \\
    --progress \\
    --stats 30s \\
    ${dry_run} \\
    --create-empty-src-dirs \\
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
