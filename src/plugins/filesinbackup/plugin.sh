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
                            directory to scan for files. [Default = "/projects/{standard,regulated,restricted}/GROUP/shared/disaster_recovery"]

    -l|--log_dir <STRING>   Absolute or relative path to the directory where log files
                            are saved. [Default = "/projects/{standard,regulated,restricted}/GROUP/shared/cephtools/filesinbackup"]
    
    -v|--verbose            Verbose mode (print additional info).
                            
    -t|--threads <INT>      Threads to use for uploading with rclone. [Default = 8].
    
    -m|--md5sum             Generate MD5 checksums for files in both disaster recovery 
                            and ceph bucket. [Default = off, checksums not generated]
    

Description:
  Generate lists of files in a group's disaster_recovery folder and in a bucket on Tier 2 storage. 
  
Help (print this screen):
    ${_ME} help filesinbackup

Questions: Please submit an issue on Github or lmp-help@msi.umn.edu
GitHub: https://github.com/umn-msi-lmnp/cephtools

Version: @VERSION_SHORT@
---------------------------------------------------------------------
HEREDOC
}

plugin_main() {
    # Note: Don't exit early for no arguments - let validation handle required params

    # Parse Options ###############################################################

    # Initialize program option variables.
    local _bucket=
    local _bucket_provided=0
    local _remote="myremote"
    local _disaster_recovery_dir=
    local _disaster_recovery_dir_provided=0
    local _log_dir=
    local _log_dir_provided=0
    local _group=
    local _verbose=0
    local _threads="8"
    local _md5sum=0

    # Parse command line arguments
    while ((${#}))
    do
        __arg="${1:-}"
        __val="${2:-}"

        case "${__arg}" in
        -v|--verbose)
            _verbose=1
            ;;
        -m|--md5sum)
            _md5sum=1
            ;;
        -r|--remote)
            _remote="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -b|--bucket)
            _bucket="$(__get_option_value "${__arg}" "${__val:-}")"
            _bucket_provided=1
            shift
            ;;
        -g|--group)
            _group="$(__get_option_value "${__arg}" "${__val:-}")"
            shift
            ;;
        -d|--disaster_recovery_dir)
            _disaster_recovery_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            _disaster_recovery_dir_provided=1
            shift
            ;;
        -l|--log_dir)
            _log_dir="$(__get_option_value "${__arg}" "${__val:-}")"
            _log_dir_provided=1
            shift
            ;;
        -t|--threads)
            _validate_threads "${__val:-}"
            _threads="${__val}"
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

    local _project_root=
    if [[ $_disaster_recovery_dir_provided -eq 0 || ( $_log_dir_provided -eq 0 && -z "${TEST_OUTPUT_DIR:-}" ) ]]; then
        _project_root="$(_resolve_group_project_root "$_group")"
    fi

    # Set defaults based on group if not explicitly provided
    if [[ $_bucket_provided -eq 0 ]]; then
        _bucket="data-delivery-${_group}"
    fi
    _bucket="$(__validate_bucket_name "$_bucket")"
    
    if [[ $_disaster_recovery_dir_provided -eq 0 ]]; then
        _disaster_recovery_dir="${_project_root}/shared/disaster_recovery"
    fi
    
    if [[ $_log_dir_provided -eq 0 ]]; then
        # Use TEST_OUTPUT_DIR in test environment
        if [[ -n "${TEST_OUTPUT_DIR:-}" ]]; then
            _log_dir="$TEST_OUTPUT_DIR/filesinbackup"
        else
            _log_dir="${_project_root}/shared/cephtools/filesinbackup"
        fi
    fi

    _verb printf "Program options used:\\n"
    _verb printf "remote: %s\\n" "$_remote"
    _verb printf "bucket: %s\\n" "$_bucket"
    _verb printf "group: %s\\n" "$_group"
    _verb printf "disaster_recovery_dir: %s\\n" "$_disaster_recovery_dir"
    _verb printf "log_dir: %s\\n" "$_log_dir"
    _verb printf "threads: %s\\n" "$_threads"
    _verb printf "md5sum: %s\\n" "$_md5sum"

    # Execute the main workflow
    _execute_filesinbackup_workflow "$_remote" "$_bucket" "$_group" "$_disaster_recovery_dir" "$_log_dir" "$_threads" "$_md5sum"
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
    local md5sum="$7"

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
    _create_filesinbackup_slurm_script "$remote" "$bucket" "$group" "$disaster_recovery_dir" "$work_dir" "$threads" "$timestamp" "$md5sum"

    _info printf "Change into the log dir and launch the slurm job:\\n"
    _info printf "cd %s && sbatch %s.slurm\\n" "$work_dir" "${group}_${timestamp}"
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
    local md5sum="$8"

    local prefix="${group}_${timestamp}"
    local script_name="${prefix}.slurm"
    local work_dir_q
    printf -v work_dir_q '%q' "$work_dir"

    _write_slurm_header "$script_name" 2:00:00 "$threads" 16gb "$remote" 0007
    cat >> "$script_name" <<EOF
# Change to working directory
cd ${work_dir_q}

echo "Starting filesinbackup listing at \$(date)"
echo "Group: ${group}"
echo "Bucket: ${bucket}"
echo "Disaster Recovery Directory: ${disaster_recovery_dir}"

# Generate file lists
echo "Generating disaster recovery file list..."
if [[ -d "${disaster_recovery_dir}" ]]; then
    find "${disaster_recovery_dir}" -type f -exec realpath {} \\; 2> ${prefix}.disaster_recovery_find.err | sort > ${prefix}.disaster_recovery_files.txt
    echo "Found \$(wc -l < ${prefix}.disaster_recovery_files.txt) files in disaster recovery"
    echo "File list saved as: ${prefix}.disaster_recovery_files.txt"
    
    # Check if find had errors
    if [[ -s ${prefix}.disaster_recovery_find.err ]]; then
        echo "WARNING: Find command encountered errors (likely permission issues)"
        echo "Error log saved as: ${prefix}.disaster_recovery_find.err"
        echo "Error count: \$(wc -l < ${prefix}.disaster_recovery_find.err)"
    else
        rm -f ${prefix}.disaster_recovery_find.err
    fi
    
$(if [[ "$md5sum" == "1" ]]; then
    cat <<'MD5_DR_EOF'
    # Generate MD5 checksums for disaster recovery files
    echo "Generating MD5 checksums for disaster recovery files..."
    if [[ -s ${prefix}.disaster_recovery_files.txt ]]; then
        rclone md5sum "${disaster_recovery_dir}" 2> ${prefix}.disaster_recovery_md5sum.err > ${prefix}.disaster_recovery_files.md5
        echo "MD5 checksums saved as: ${prefix}.disaster_recovery_files.md5"
        
        # Check if md5sum had errors
        if [[ -s ${prefix}.disaster_recovery_md5sum.err ]]; then
            echo "WARNING: MD5sum encountered errors"
            echo "Error log saved as: ${prefix}.disaster_recovery_md5sum.err"
        else
            rm -f ${prefix}.disaster_recovery_md5sum.err
        fi
    fi
MD5_DR_EOF
else
    echo "    echo \"Skipping MD5 checksum generation (not requested)\""
fi)
else
    echo "Disaster recovery directory not found: ${disaster_recovery_dir}"
    touch ${prefix}.disaster_recovery_files.txt
fi

echo "Generating ceph bucket file list..."
if rclone lsf ${remote}:${bucket} 2> ${prefix}.ceph_bucket_check.err > /dev/null; then
    rclone lsf -R ${remote}:${bucket} 2> ${prefix}.ceph_bucket_lsf.err | sed "s|^|s3://${bucket}/|" | sort > ${prefix}.${bucket}_tier2_files.txt
    echo "Found \$(wc -l < ${prefix}.${bucket}_tier2_files.txt) files in ceph bucket"
    echo "File list saved as: ${prefix}.${bucket}_tier2_files.txt"
    
    # Check if lsf had errors
    if [[ -s ${prefix}.ceph_bucket_lsf.err ]]; then
        echo "WARNING: Rclone lsf encountered errors"
        echo "Error log saved as: ${prefix}.ceph_bucket_lsf.err"
    else
        rm -f ${prefix}.ceph_bucket_lsf.err
    fi
    rm -f ${prefix}.ceph_bucket_check.err
    
$(if [[ "$md5sum" == "1" ]]; then
    cat <<'MD5_CEPH_EOF'
    # Generate MD5 checksums for ceph bucket files
    echo "Generating MD5 checksums for ceph bucket files..."
    if [[ -s ${prefix}.${bucket}_tier2_files.txt ]]; then
        rclone md5sum ${remote}:${bucket} 2> ${prefix}.ceph_bucket_md5sum.err > ${prefix}.${bucket}_tier2_files.md5
        echo "MD5 checksums saved as: ${prefix}.${bucket}_tier2_files.md5"
        
        # Check if md5sum had errors
        if [[ -s ${prefix}.ceph_bucket_md5sum.err ]]; then
            echo "WARNING: MD5sum encountered errors"
            echo "Error log saved as: ${prefix}.ceph_bucket_md5sum.err"
        else
            rm -f ${prefix}.ceph_bucket_md5sum.err
        fi
    fi
MD5_CEPH_EOF
else
    echo "    echo \"Skipping MD5 checksum generation (not requested)\""
fi)
else
    echo "Cannot access ceph bucket or bucket is empty: ${bucket}"
    if [[ -s ${prefix}.ceph_bucket_check.err ]]; then
        echo "Error log saved as: ${prefix}.ceph_bucket_check.err"
    fi
    touch ${prefix}.${bucket}_tier2_files.txt
fi

echo "File listing completed at \$(date)"
echo "File lists available in: ${work_dir}"
EOF

    chmod +x "$script_name"
    

}
