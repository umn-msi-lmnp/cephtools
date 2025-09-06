#!/usr/bin/env bash
###############################################################################
# filesinbackup Plugin for cephtools
# Print list of files in a group's disaster_recovery folder and a list of files 
# in a bucket on Tier 2 and emails those lists to the group PI.
###############################################################################

# Plugin metadata
PLUGIN_NAME="filesinbackup"

PLUGIN_DESCRIPTION="List files in disaster recovery and ceph bucket for comparison"

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
  Print list of files in a group's disaster_recovery folder and a list of files in a bucket on Tier 2 
  and emails those lists to the group PI. 
  
Help (print this screen):
    ${_ME} help filesinbackup

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
    local _bucket="data-delivery-$(id -ng)"
    local _remote="myremote"
    local _disaster_recovery_dir="$MSIPROJECT/shared/disaster_recovery"
    local _log_dir="$MSIPROJECT/shared/cephtools/filesinbackup"
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

    # Create log directory if needed
    if [[ ! -d "$log_dir" ]]; then
        _info printf "Creating log directory: %s\\n" "$log_dir"
        mkdir -p "$log_dir"
        chmod g+rwx "$log_dir"
    fi

    # Create working directory
    local timestamp="$(date +"%Y-%m-%d-%H%M%S")"
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

_create_comparison_report() {
    local bucket="$1"
    local group="$2" 
    local work_dir="$3"

    local report_file="${work_dir}/backup_comparison_report.txt"
    
    cat > "$report_file" <<EOF
Backup Comparison Report
========================
Generated: $(date)
Group: ${group}
Bucket: ${bucket}

Summary:
--------
Disaster Recovery Files: $(wc -l < "${work_dir}/disaster_recovery_files.txt")
Ceph Bucket Files: $(wc -l < "${work_dir}/ceph_bucket_files.txt")

Files only in Disaster Recovery:
EOF

    # Files in disaster recovery but not in ceph
    comm -23 "${work_dir}/disaster_recovery_files.txt" "${work_dir}/ceph_bucket_files.txt" >> "$report_file"
    
    cat >> "$report_file" <<EOF

Files only in Ceph Bucket:
EOF

    # Files in ceph but not in disaster recovery
    comm -13 "${work_dir}/disaster_recovery_files.txt" "${work_dir}/ceph_bucket_files.txt" >> "$report_file"

    cat >> "$report_file" <<EOF

Files in both locations:
EOF

    # Files in both locations
    comm -12 "${work_dir}/disaster_recovery_files.txt" "${work_dir}/ceph_bucket_files.txt" >> "$report_file"

    _info printf "Created comparison report: %s\\n" "$report_file"
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
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=${threads}
#SBATCH --mem=8gb
#SBATCH --mail-type=ALL
#SBATCH --mail-user=\${USER}@umn.edu
#SBATCH --error=%x.e%j
#SBATCH --output=%x.o%j

# Load required modules
module load rclone

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

echo "Starting filesinbackup analysis at \$(date)"
echo "Group: ${group}"
echo "Bucket: ${bucket}"
echo "Disaster Recovery Directory: ${disaster_recovery_dir}"

# Generate updated file lists
echo "Generating disaster recovery file list..."
if [[ -d "${disaster_recovery_dir}" ]]; then
    find "${disaster_recovery_dir}" -type f -printf '%P\\n' 2>/dev/null | sort > ${prefix}.disaster_recovery_files.txt
    echo "Found \$(wc -l < ${prefix}.disaster_recovery_files.txt) files in disaster recovery"
else
    echo "Disaster recovery directory not found: ${disaster_recovery_dir}"
    touch ${prefix}.disaster_recovery_files.txt
fi

echo "Generating ceph bucket file list..."
if rclone lsf ${remote}:${bucket} &>/dev/null; then
    rclone lsf -R ${remote}:${bucket} 2>/dev/null | sort > ${prefix}.ceph_bucket_files.txt
    echo "Found \$(wc -l < ${prefix}.ceph_bucket_files.txt) files in ceph bucket"
else
    echo "Cannot access ceph bucket or bucket is empty: ${bucket}"
    touch ${prefix}.ceph_bucket_files.txt
fi

# Create comparison files
echo "Creating comparison files..."

# Files in disaster recovery but not in ceph
comm -23 ${prefix}.disaster_recovery_files.txt ${prefix}.ceph_bucket_files.txt > ${prefix}.missing_from_ceph.txt

# Files in ceph but not in disaster recovery  
comm -13 ${prefix}.disaster_recovery_files.txt ${prefix}.ceph_bucket_files.txt > ${prefix}.missing_from_disaster_recovery.txt

echo "Created comparison files:"
echo "  ${prefix}.missing_from_ceph.txt"
echo "  ${prefix}.missing_from_disaster_recovery.txt"

echo "Analysis completed at \$(date)"
echo "Reports available in: ${work_dir}"
EOF

    chmod +x "$script_name"
    

}