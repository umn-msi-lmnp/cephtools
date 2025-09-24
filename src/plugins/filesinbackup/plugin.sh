#!/usr/bin/env bash
###############################################################################
# filesinbackup Plugin for cephtools
# Print list of files in a group's disaster_recovery folder and a list of files 
# in a bucket on Tier 2 and emails those lists to the group PI.
###############################################################################

# Plugin metadata
PLUGIN_NAME="filesinbackup"

PLUGIN_DESCRIPTION="List files in disaster recovery and ceph bucket"

###############################################################################
# Plugin Interface Functions
###############################################################################

plugin_describe() {
cat <<HEREDOC
---------------------------------------------------------------------
Usage:
    ${_ME} filesinbackup [options] --group <GROUP>

Options:                            
    -r|--remote <STRING>    [Optional] Rclone remote name. (use "rclone listremotes" for available
                            remotes). Rclone remotes must be set up using "rclone init"
                            and can be viewed at: ~/.config/rclone/rclone.conf. This option
                            is not required. If you do not specify --remote, the tool will 
                            automatically identify your MSI ceph keys and set the remote. 
                            This option was left here for backward compatibility.

    -b|--bucket <STRING>    [Optional] Name of the ceph bucket that data should be used for the 
                            transfer. [Default = "data-delivery-$(id -ng)"]
    
    -g|--group <STRING>     MSI group id. Your current group is $(id -ng).

    -d|--disaster_recovery_dir <STRING>    Absolute or relative path to the disaster recovery 
                            directory to scan for files. [Default = "$MSIPROJECT/shared/disaster_recovery"]

    -l|--log_dir <STRING>   Absolute or relative path to the directory where log files
                            are saved. [Default = "$MSIPROJECT/shared/cephtools/filesinbackup"]
    
    -v|--verbose            Verbose mode (print additional info).
                            
    -t|--threads <INT>      Threads to use for uploading with rclone. [Default = 8].
    

Description:
  Generate lists of files in a group's disaster_recovery folder and in a bucket on Tier 2 storage. 
  
Help (print this screen):
    ${_ME} help filesinbackup

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
GitHub: https://github.umn.edu/lmnp/cephtools

Version: @VERSION_SHORT@
---------------------------------------------------------------------
HEREDOC
}

plugin_main() {
    # Note: Don't exit early for no arguments - let validation handle required params

    # Parse Options ###############################################################

    # Initialize program option variables.
    local _bucket="data-delivery-$(id -ng)"
    local _remote="myremote"
    local _disaster_recovery_dir="$MSIPROJECT/shared/disaster_recovery"
    # Set default log directory - use TEST_OUTPUT_DIR in test environment
    if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
        local _log_dir="$TEST_OUTPUT_DIR/filesinbackup"
    else
        local _log_dir="$MSIPROJECT/shared/cephtools/filesinbackup"
    fi
    local _group=
    local _verbose=0
    local _threads="8"

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

    # Parse command line arguments
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -v|--verbose)
            _verbose=1
            ;;
        -r|--remote)
            _remote="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -b|--bucket)
            _bucket="$(__validate_bucket_name "$(__get_option_value "${__arg}" "${__val:-}")")"
            shift
            ;;
        -g|--group)
            _group="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -d|--disaster_recovery_dir)
            _disaster_recovery_dir="$(__get_option_value "${__arg}" "${__val:-}")"
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

    # Validate required parameters
    if [[ -z "${_group:-}" ]]; then
        plugin_describe
        _exit_1 printf "Option '--group' is required.\\n"
    fi

    _verb printf "Program options used:\\n"
    _verb printf "remote: %s\\n" "$_remote"
    _verb printf "bucket: %s\\n" "$_bucket"
    _verb printf "group: %s\\n" "$_group"
    _verb printf "disaster_recovery_dir: %s\\n" "$_disaster_recovery_dir"
    _verb printf "log_dir: %s\\n" "$_log_dir"
    _verb printf "threads: %s\\n" "$_threads"

    # Execute the main workflow
    _execute_filesinbackup_workflow "$_remote" "$_bucket" "$_group" "$_disaster_recovery_dir" "$_log_dir" "$_threads"
}

###############################################################################
# Helper Functions
###############################################################################

_execute_filesinbackup_workflow() {
    local remote="$1"
    local bucket="$2"
    local group="$3"
    local disaster_recovery_dir="$4"
    local log_dir="$5"
    local threads="$6"

    # Set umask to create files with 660 (rw-rw----) and dirs with 770 (rwxrwx---)
    umask 0007

    # Check rclone version and load appropriate module
    _info printf "Checking rclone version...\\n"
    _check_rclone_version

    # Create log directory if needed
    if [[ ! -d "$log_dir" ]]; then
        _info printf "Creating log directory: %s\\n" "$log_dir"
        mkdir -p "$log_dir"
        chmod g+rwx "$log_dir"
    fi

    # Create working directory with unique timestamp (including microseconds for concurrency)
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")-$(date +"%N" | cut -c1-6)"
    local work_dir="${log_dir}/filesinbackup_${group}_${timestamp}"
    

    mkdir -p "$work_dir"
    cd "$work_dir"

    # Setup rclone credentials if using default remote (for validation only)
    _setup_rclone_credentials "$remote"

    # Create SLURM script for analysis
    _create_filesinbackup_slurm_script "$remote" "$bucket" "$group" "$disaster_recovery_dir" "$work_dir" "$threads" "$timestamp"

    _info printf "Change into the log dir and launch the slurm job:\\n"
    _info printf "cd %s && sbatch %s.slurm\\n" "$work_dir" "${group}_${timestamp}"
}

_setup_rclone_credentials() {
    local remote="$1"
    
    # Setup rclone credentials if using default remote
    if [[ "$remote" == "myremote" ]]; then
        if command -v s3info >/dev/null 2>&1; then
            export RCLONE_CONFIG_MYREMOTE_TYPE=s3
            export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE
            RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID="$(s3info --keys | awk '{print $1}')"
            RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY="$(s3info --keys | awk '{print $2}')"
            export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY
            export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu
            export RCLONE_CONFIG_MYREMOTE_ACL=private
            export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph
            _debug printf "Rclone credentials configured for myremote\\n"
        else
            _exit_1 printf "s3info failed\\n"
        fi
    fi
}

_generate_file_lists() {
    local remote="$1"
    local bucket="$2"
    local disaster_recovery_dir="$3"
    local work_dir="$4"

    _info printf "Generating file lists...\\n"

    # Generate disaster recovery file list
    if [[ -d "$disaster_recovery_dir" ]]; then
        _verb printf "Listing files in disaster recovery: %s\\n" "$disaster_recovery_dir"
        find "$disaster_recovery_dir" -type f -printf '%P\\n' 2>/dev/null | sort > "${work_dir}/disaster_recovery_files.txt"
        local dr_count="$(wc -l < "${work_dir}/disaster_recovery_files.txt")"
        _info printf "Found %s files in disaster recovery\\n" "$dr_count"
    else
        _warn printf "Disaster recovery directory not found: %s\\n" "$disaster_recovery_dir"
        touch "${work_dir}/disaster_recovery_files.txt"
    fi

    # Generate ceph bucket file list
    _verb printf "Listing files in ceph bucket: %s\\n" "$bucket"
    
    # Check if we can access the bucket
    if rclone lsf ${remote}:${bucket} &>/dev/null; then
        rclone lsf -R ${remote}:${bucket} 2>/dev/null | sort > "${work_dir}/ceph_bucket_files.txt"
        local bucket_count="$(wc -l < "${work_dir}/ceph_bucket_files.txt")"
        _info printf "Found %s files in ceph bucket\\n" "$bucket_count"
    else
        _warn printf "Cannot access ceph bucket or bucket is empty: %s\\n" "$bucket"
        touch "${work_dir}/ceph_bucket_files.txt"
    fi
}



_create_filesinbackup_slurm_script() {
    local remote="$1"
    local bucket="$2"
    local group="$3"
    local disaster_recovery_dir="$4"
    local work_dir="$5"
    local threads="$6"
    local timestamp="$7"

    local prefix="${group}_${timestamp}"
    local script_name="${prefix}.slurm"

    cat > "$script_name" <<EOF
#!/bin/bash
#SBATCH --time=2:00:00
#SBATCH --partition=msismall
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=16gb
#SBATCH --mail-type=ALL
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Generated by cephtools @VERSION_SHORT@
# Build Date: @BUILD_DATE@
# Git Branch: @GIT_CURRENT_BRANCH@
# Git Commit: @GIT_LATEST_COMMIT_SHORT@@GIT_LATEST_COMMIT_DIRTY@
# Git Commit Date: @GIT_LATEST_COMMIT_DATETIME@
# Source: @GIT_WEB_URL@

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

# Set umask for group-writable files (660) and directories (770)
umask 0007

# Set up credentials for myremote if needed
$(if [[ "$remote" == "myremote" ]]; then
    cat <<'CRED_EOF'
export RCLONE_CONFIG_MYREMOTE_TYPE=s3
export RCLONE_CONFIG_MYREMOTE_ENV_AUTH=FALSE
export RCLONE_CONFIG_MYREMOTE_ACCESS_KEY_ID=$(s3info --keys | awk '{print $1}')
export RCLONE_CONFIG_MYREMOTE_SECRET_ACCESS_KEY=$(s3info --keys | awk '{print $2}')
export RCLONE_CONFIG_MYREMOTE_ENDPOINT=s3.msi.umn.edu
export RCLONE_CONFIG_MYREMOTE_ACL=private
export RCLONE_CONFIG_MYREMOTE_PROVIDER=Ceph
CRED_EOF
fi)

# Change to working directory
cd ${work_dir}

echo "SLURM Script generated by cephtools @VERSION_SHORT@"
echo "Build Date: @BUILD_DATE@"
echo "Git Info: @GIT_CURRENT_BRANCH@@GIT_LATEST_COMMIT_SHORT@@GIT_LATEST_COMMIT_DIRTY@ (@GIT_LATEST_COMMIT_DATETIME@)"
echo "Source: @GIT_WEB_URL@"
echo ""

echo "Starting filesinbackup listing at \$(date)"
echo "Group: ${group}"
echo "Bucket: ${bucket}"
echo "Disaster Recovery Directory: ${disaster_recovery_dir}"

# Generate file lists
echo "Generating disaster recovery file list..."
if [[ -d "${disaster_recovery_dir}" ]]; then
    find "${disaster_recovery_dir}" -type f -exec realpath {} \\; 2>/dev/null | sort > ${prefix}.disaster_recovery_files.txt
    echo "Found \$(wc -l < ${prefix}.disaster_recovery_files.txt) files in disaster recovery"
    echo "File list saved as: ${prefix}.disaster_recovery_files.txt"
    
    # Generate MD5 checksums for disaster recovery files
    echo "Generating MD5 checksums for disaster recovery files..."
    if [[ -s ${prefix}.disaster_recovery_files.txt ]]; then
        rclone md5sum "${disaster_recovery_dir}" 2>/dev/null > ${prefix}.disaster_recovery_files.md5
        echo "MD5 checksums saved as: ${prefix}.disaster_recovery_files.md5"
    else
        touch ${prefix}.disaster_recovery_files.md5
    fi
else
    echo "Disaster recovery directory not found: ${disaster_recovery_dir}"
    touch ${prefix}.disaster_recovery_files.txt
    touch ${prefix}.disaster_recovery_files.md5
fi

echo "Generating ceph bucket file list..."
if rclone lsf ${remote}:${bucket} &>/dev/null; then
    rclone lsf -R ${remote}:${bucket} 2>/dev/null | sed "s|^|s3://${bucket}/|" | sort > ${prefix}.${bucket}_tier2_files.txt
    echo "Found \$(wc -l < ${prefix}.${bucket}_tier2_files.txt) files in ceph bucket"
    echo "File list saved as: ${prefix}.${bucket}_tier2_files.txt"
    
    # Generate MD5 checksums for ceph bucket files
    echo "Generating MD5 checksums for ceph bucket files..."
    if [[ -s ${prefix}.${bucket}_tier2_files.txt ]]; then
        rclone md5sum ${remote}:${bucket} 2>/dev/null > ${prefix}.${bucket}_tier2_files.md5
        echo "MD5 checksums saved as: ${prefix}.${bucket}_tier2_files.md5"
    else
        touch ${prefix}.${bucket}_tier2_files.md5
    fi
else
    echo "Cannot access ceph bucket or bucket is empty: ${bucket}"
    touch ${prefix}.${bucket}_tier2_files.txt
    touch ${prefix}.${bucket}_tier2_files.md5
fi

echo "File listing completed at \$(date)"
echo "File lists available in: ${work_dir}"
EOF

    chmod +x "$script_name"
    

}
